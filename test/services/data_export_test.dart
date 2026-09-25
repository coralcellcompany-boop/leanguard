import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leanguard/core/data/api_repository.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/services/data_export_service.dart';
import 'package:share_plus/share_plus.dart';

class ExportRepository extends LeanRepository {
  ExportRepository() : super(store: MemoryLocalStore()) {
    userId = 'account-a';
  }
  Json response = {
    'schema_version': 1,
    'user_id': 'account-a',
    'tables': {
      'weight_entries': [
        {'kg': 80.2},
      ],
    },
  };
  String? called;
  Json? body;
  Completer<Json>? exportResult;
  @override
  Future<Json> invoke(String name, [Json body = const {}]) async {
    called = name;
    this.body = body;
    return exportResult == null ? response : exportResult!.future;
  }
}

void main() {
  const backend = 'https://api.leanguard.test';
  const url =
      '$backend/v1/exports/account-a/12345678-1234-1234-1234-123456789abc.json?expires=9999999999999&signature=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  late Directory temp;
  late ExportRepository repository;
  late List<ShareParams> shared;
  late List<int> sharedBytes;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('leanguard-export-test-');
    repository = ExportRepository();
    shared = [];
    sharedBytes = [];
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  DataExportService service({http.Client? client, Duration? timeout}) =>
      DataExportService(
        repository,
        backendBaseUrl: backend,
        temporaryDirectory: () async => temp,
        httpClientFactory: () =>
            client ?? MockClient((_) async => http.Response('', 500)),
        downloadTimeout: timeout ?? const Duration(seconds: 300),
        share: (params) async {
          shared.add(params);
          sharedBytes = await params.files!.single.readAsBytes();
          return const ShareResult('selected', ShareResultStatus.success);
        },
      );

  Future<void> expectNoPartialFiles() async {
    final files = await temp
        .list(recursive: true)
        .where((e) => e is File)
        .toList();
    expect(files, isEmpty);
  }

  test(
    'inline export shares caller records with an actual JSON filename',
    () async {
      final result = await service().exportAndShare();
      expect(result.status, ShareResultStatus.success);
      expect(jsonDecode(utf8.decode(sharedBytes)), repository.response);
      expect(shared.single.files!.single.mimeType, 'application/json');
      expect(
        shared.single.fileNameOverrides!.single,
        matches(r'^leanguard-export-\d{4}-\d{2}-\d{2}\.json$'),
      );
      expect(repository.called, 'data-export');
    },
  );

  test(
    'large signed export streams actual data without sharing descriptor or bearer token',
    () async {
      repository.response = {'download_url': url, 'expires_in_seconds': 600};
      final bytes = utf8.encode(
        '{"tables":{"protein_entries":[{"grams":35}]}}',
      );
      final client = MockClient.streaming((request, body) async {
        expect(request.url.toString(), url);
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('x-firebase-appcheck'), isFalse);
        return http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 14), bytes.sublist(14)]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await service(client: client).exportAndShare();
      expect(sharedBytes, bytes);
      expect(utf8.decode(sharedBytes), isNot(contains('download_url')));
    },
  );

  test('archive export preserves binary bytes and archive MIME type', () async {
    repository.response = {'download_url': url};
    final bytes = [80, 75, 3, 4, 0, 255, 42];
    await service(
      client: MockClient(
        (_) async => http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'application/zip'},
        ),
      ),
    ).exportAndShare();
    expect(sharedBytes, bytes);
    expect(shared.single.files!.single.mimeType, 'application/zip');
    expect(shared.single.fileNameOverrides!.single, endsWith('.zip'));
  });

  test(
    'rejects untrusted, unsigned, insecure and other-owner download URLs before network access',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      for (final unsafe in [
        url.replaceFirst('https:', 'http:'),
        url.replaceFirst('api.leanguard.test', 'example.com'),
        url.replaceFirst('account-a/', 'account-b/'),
        url.replaceFirst('/v1/', '/v2/'),
        url.split('?').first,
        '$url#fragment',
      ]) {
        repository.response = {'download_url': unsafe};
        await expectLater(
          service(client: client).exportAndShare(),
          throwsStateError,
        );
      }
      expect(requests, 0);
      expect(shared, isEmpty);
      await expectNoPartialFiles();
    },
  );

  test(
    'expired or redirecting downloads cannot open the share sheet',
    () async {
      repository.response = {'download_url': url};
      for (final status in [403, 404, 302]) {
        await expectLater(
          service(
            client: MockClient(
              (_) async => http.Response('unavailable', status),
            ),
          ).exportAndShare(),
          throwsStateError,
        );
      }
      expect(shared, isEmpty);
      await expectNoPartialFiles();
    },
  );

  test(
    'unexpected HTML and empty downloads do not become health exports',
    () async {
      repository.response = {'download_url': url};
      for (final response in [
        http.Response(
          '<html>error</html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
        http.Response('', 200, headers: {'content-type': 'application/json'}),
      ]) {
        await expectLater(
          service(client: MockClient((_) async => response)).exportAndShare(),
          throwsStateError,
        );
      }
      expect(shared, isEmpty);
      await expectNoPartialFiles();
    },
  );

  test(
    'account switch while export function runs prevents download and sharing',
    () async {
      repository.exportResult = Completer<Json>();
      final future = service().exportAndShare();
      repository.userId = 'account-b';
      repository.exportResult!.complete({'download_url': url});
      await expectLater(future, throwsStateError);
      expect(shared, isEmpty);
      await expectNoPartialFiles();
    },
  );

  test('account switch during download removes partial private file', () async {
    repository.response = {'download_url': url};
    Stream<List<int>> chunks() async* {
      yield utf8.encode('{"tables":');
      repository.userId = 'account-b';
      yield utf8.encode('{}}');
    }

    final client = MockClient.streaming(
      (_, body) async => http.StreamedResponse(
        chunks(),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await expectLater(
      service(client: client).exportAndShare(),
      throwsStateError,
    );
    expect(shared, isEmpty);
    await expectNoPartialFiles();
  });

  test('network timeout leaves no export and permits a new attempt', () async {
    repository.response = {'download_url': url};
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await expectLater(
      service(
        client: client,
        timeout: const Duration(milliseconds: 5),
      ).exportAndShare(),
      throwsA(isA<TimeoutException>()),
    );
    expect(shared, isEmpty);
    await expectNoPartialFiles();
  });

  test('network errors never expose the signed download credential', () async {
    repository.response = {'download_url': url};
    final client = MockClient(
      (_) async =>
          throw http.ClientException('Connection failed', Uri.parse(url)),
    );
    await expectLater(
      service(client: client).exportAndShare(),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          isNot(contains('signature')),
        ),
      ),
    );
    expect(shared, isEmpty);
    await expectNoPartialFiles();
  });

  test('preview and wrong-owner inline exports are never shared', () async {
    repository.userId = 'preview';
    await expectLater(service().exportAndShare(), throwsStateError);
    expect(repository.called, isNull);
    repository.userId = 'account-b';
    await expectLater(service().exportAndShare(), throwsStateError);
    expect(shared, isEmpty);
    await expectNoPartialFiles();
  });

  test(
    'deletion requires typed confirmation and clears retained export copies after success',
    () async {
      await service().exportAndShare();
      expect(await temp.list(recursive: true).any((e) => e is File), isTrue);
      await expectLater(
        service().deleteAccount(confirmation: 'delete'),
        throwsFormatException,
      );
      expect(repository.called, 'data-export');
      await service().deleteAccount(confirmation: 'DELETE');
      expect(repository.called, 'delete-account');
      expect(repository.body, {'confirmation': 'DELETE'});
      await expectNoPartialFiles();
    },
  );

  test(
    'native temporary-directory failure cannot undo completed account deletion',
    () async {
      final exporter = DataExportService(
        repository,
        temporaryDirectory: () async =>
            throw StateError('Native directory unavailable'),
        share: (_) async =>
            const ShareResult('', ShareResultStatus.unavailable),
      );
      await exporter.deleteAccount(confirmation: 'DELETE');
      expect(repository.called, 'delete-account');
    },
  );

  test('privacy endpoints allow300s while coaching retains the35s bound', () {
    for (final endpoint in [
      'data-export',
      'dataExport',
      'delete-account',
      'deleteAccount',
    ]) {
      expect(
        ApiRepositoryRemote.requestTimeout(endpoint),
        const Duration(seconds: 300),
      );
    }
    for (final endpoint in ['coach', 'sync-health-activity', 'approve-plan']) {
      expect(
        ApiRepositoryRemote.requestTimeout(endpoint),
        const Duration(seconds: 35),
      );
    }
  });
}
