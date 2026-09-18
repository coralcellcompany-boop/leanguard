import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/repository.dart';

/// Export is an explicit user action. Firebase ID/App Check authenticate the
/// function; the short-lived Storage URL authenticates its own download. Never
/// forward Firebase credentials to that URL or expose it in the shared file.
class DataExportService {
  DataExportService(
    this.repository, {
    http.Client Function()? httpClientFactory,
    Future<Directory> Function()? temporaryDirectory,
    Future<ShareResult> Function(ShareParams)? share,
    this.storageBucket = AppConfig.firebaseStorageBucket,
    this.downloadTimeout = const Duration(seconds: 300),
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _share = share ?? SharePlus.instance.share;

  final LeanRepository repository;
  final http.Client Function() _httpClientFactory;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<ShareResult> Function(ShareParams) _share;
  final String storageBucket;
  final Duration downloadTimeout;

  String _requireOwner() {
    final owner = repository.userId;
    if (owner == null || repository.isDemo) {
      throw StateError('Sign in to export or delete your data.');
    }
    return owner;
  }

  void _checkOwner(String owner) {
    if (repository.userId != owner || repository.isDemo) {
      throw StateError('Your account changed. Request a new export.');
    }
  }

  Future<Directory> _exportRoot() async {
    final temporary = await _temporaryDirectory();
    return Directory(
      '${temporary.path}/leanguard_exports',
    ).create(recursive: true);
  }

  /// Keep successful files briefly: on Android, a share result can arrive
  /// before the receiving app has finished reading the URI. Failed downloads
  /// are removed immediately; older successful copies are pruned next export.
  Future<void> _prune(Directory root) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory &&
          entry.path.split('/').last.startsWith('export-')) {
        final stat = await entry.stat();
        if (stat.modified.isBefore(cutoff)) await entry.delete(recursive: true);
      }
    }
  }

  Uri _downloadUri(Object? value, String owner) {
    final uri = value is String ? Uri.tryParse(value) : null;
    final segments = uri?.pathSegments ?? const <String>[];
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'storage.googleapis.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        storageBucket.isEmpty ||
        segments.length < 4 ||
        segments[0] != storageBucket ||
        segments[1] != 'exports' ||
        segments[2] != owner ||
        ![
          'Signature',
          'X-Goog-Signature',
        ].any((key) => uri.queryParameters[key]?.isNotEmpty ?? false)) {
      throw StateError('The export download could not be verified. Try again.');
    }
    return uri;
  }

  Future<({File file, String mime})> _download(
    Uri uri,
    Directory directory,
    String owner,
  ) async {
    final client = _httpClientFactory();
    final abort = Completer<void>();
    var timedOut = false;
    final timer = Timer(downloadTimeout, () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
      client.close();
    });
    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final response = await client.send(request).timeout(downloadTimeout);
      if (response.statusCode != 200) {
        throw StateError(
          'The export download expired or failed. Request a new export.',
        );
      }
      final mime = response.headers['content-type']?.split(';').first.trim();
      final extension = switch (mime) {
        'application/json' => 'json',
        'application/zip' => 'zip',
        'application/gzip' => 'json.gz',
        _ => throw StateError('The export download has an unsupported format.'),
      };
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${directory.path}/leanguard-export-$date.$extension');
      final sink = file.openWrite();
      var length = 0;
      try {
        // addStream propagates filesystem backpressure instead of buffering an
        // arbitrarily large export through repeated non-awaitable sink.add.
        await sink.addStream(
          response.stream.timeout(downloadTimeout).map((chunk) {
            _checkOwner(owner);
            if (timedOut) {
              throw TimeoutException('The export download timed out.');
            }
            length += chunk.length;
            return chunk;
          }),
        );
        await sink.flush();
        await sink.close();
      } catch (_) {
        // addStream may already close the file on an upstream error. Preserve
        // the original account/timeout/network failure if close also fails.
        try {
          await sink.close();
        } catch (_) {}
        rethrow;
      }
      if (timedOut) throw TimeoutException('The export download timed out.');
      if (length == 0) {
        throw StateError('The export download was empty. Try again.');
      }
      return (file: file, mime: mime!);
    } on http.RequestAbortedException {
      throw TimeoutException('The export download timed out. Try again.');
    } on http.ClientException {
      // ClientException can embed its signed URL. Keep that credential out of
      // user-facing errors and any caller's diagnostics.
      throw StateError('The export download failed. Request a new export.');
    } finally {
      timer.cancel();
      client.close();
    }
  }

  /// The native share sheet is shown only after an explicit export action and
  /// after the complete inline payload or signed large export has been written.
  Future<ShareResult> exportAndShare({Rect? sharePositionOrigin}) async {
    final owner = _requireOwner();
    final result = await repository.invoke('data-export');
    _checkOwner(owner);
    final root = await _exportRoot();
    await _prune(root);
    final directory = await root.createTemp('export-');
    try {
      final File file;
      final String mime;
      if (result.containsKey('download_url')) {
        final downloaded = await _download(
          _downloadUri(result['download_url'], owner),
          directory,
          owner,
        );
        file = downloaded.file;
        mime = downloaded.mime;
      } else {
        if (result['user_id'] != owner || result['tables'] is! Map) {
          throw StateError(
            'The service returned an invalid export. Try again.',
          );
        }
        final date = DateTime.now().toIso8601String().substring(0, 10);
        file = File('${directory.path}/leanguard-export-$date.json');
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(result),
        );
        mime = 'application/json';
      }
      _checkOwner(owner);
      final shared = await _share(
        ShareParams(
          title: 'LeanGuard data export',
          files: [XFile(file.path, mimeType: mime)],
          fileNameOverrides: [file.uri.pathSegments.last],
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return shared;
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
  }

  /// UI requires typed DELETE and explains that store billing is separate.
  Future<void> deleteAccount({required String confirmation}) async {
    if (confirmation != 'DELETE') {
      throw const FormatException('Type DELETE to confirm.');
    }
    _requireOwner();
    await repository.invoke('delete-account', {'confirmation': confirmation});
    // A filesystem cleanup failure must not hide successful remote deletion or
    // prevent the controller from clearing credentials and private caches.
    try {
      final root = await _exportRoot();
      await root.delete(recursive: true);
    } catch (_) {
      // Native temporary-directory lookup may also fail after deletion.
      // The OS also evicts this app-owned temporary directory.
    }
  }
}
