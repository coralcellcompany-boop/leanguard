import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../data/repository.dart';

class ReportService {
  static String csvCell(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';
  static String toCsv(Map<String, List<Json>> records, DateTime since) {
    final lines = <String>['record_type,date,metric,value,unit'];
    void add(
      String type,
      Object? date,
      String metric,
      Object? value,
      String unit,
    ) {
      if (value == null) return;
      final d = DateTime.tryParse(date.toString());
      if (d == null || d.isBefore(since)) return;
      lines.add([type, date, metric, value, unit].map(csvCell).join(','));
    }

    for (final row in records['weight_entries'] ?? <Json>[]) {
      add('weight', row['recorded_at'], 'weight', row['weight_kg'], 'kg');
    }
    for (final row in records['protein_entries'] ?? <Json>[]) {
      add('protein', row['recorded_at'], 'protein', row['protein_g'], 'g');
    }
    for (final row in records['daily_activities'] ?? <Json>[]) {
      add('activity', row['date'], 'steps', row['steps'], 'steps');
    }
    for (final row in records['body_measurements'] ?? <Json>[]) {
      for (final type in ['waist', 'hips', 'chest', 'arm', 'thigh']) {
        add('measurement', row['recorded_at'], type, row['${type}_cm'], 'cm');
      }
    }
    for (final row in records['workout_sets'] ?? <Json>[]) {
      add('workout_set', row['completed_at'], 'load', row['weight_kg'], 'kg');
      add('workout_set', row['completed_at'], 'reps', row['reps'], 'reps');
    }
    return '${lines.join('\r\n')}\r\n';
  }

  static Future<Uint8List> toPdf(
    Map<String, List<Json>> records,
    DateTime since, {
    bool clinician = false,
  }) async {
    final doc = pw.Document(
      title: clinician
          ? 'LeanGuard clinician conversation summary'
          : 'LeanGuard progress report',
    );
    final csv = toCsv(records, since);
    final rows = const LineSplitter()
        .convert(csv)
        .skip(1)
        .where((l) => l.isNotEmpty)
        .map((l) => l.split(',').map((s) => s.replaceAll('"', '')).toList())
        .toList();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Text(
            'LeanGuard',
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            clinician
                ? 'Your clinician conversation summary'
                : 'Your progress report',
            style: const pw.TextStyle(fontSize: 18),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Logged data since ${since.toIso8601String().substring(0, 10)}. Generated ${DateTime.now().toIso8601String().substring(0, 10)}.',
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'This report contains user-entered and imported wellness data. Missing entries are unknown. It does not diagnose muscle loss or provide treatment or medication advice.',
          ),
          if (clinician) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'Questions to discuss: How does my strength and weight trend fit my goals? Do any symptoms or appetite changes need review? What routine is appropriate for me?',
            ),
          ],
          pw.SizedBox(height: 16),
          if (rows.isEmpty)
            pw.Text('No entries in this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Record', 'Date', 'Metric', 'Value', 'Unit'],
              data: rows,
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              cellAlignment: pw.Alignment.centerLeft,
            ),
        ],
        footer: (context) => pw.Text(
          'Private - share only with people you choose. Page ${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> export(
    Map<String, List<Json>> records, {
    required String format,
    required int days,
    bool clinician = false,
  }) async {
    final today = DateTime.now();
    final since = days == 0
        ? DateTime(2000)
        : DateTime(
            today.year,
            today.month,
            today.day,
          ).subtract(Duration(days: days - 1));
    final bytes = format == 'pdf'
        ? await toPdf(records, since, clinician: clinician)
        : Uint8List.fromList(utf8.encode(toCsv(records, since)));
    await SharePlus.instance.share(
      ShareParams(
        title: 'LeanGuard report',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
        files: [
          XFile.fromData(
            bytes,
            mimeType: format == 'pdf' ? 'application/pdf' : 'text/csv',
          ),
        ],
        fileNameOverrides: [
          'leanguard-${clinician ? 'clinician' : 'progress'}-${DateTime.now().toIso8601String().substring(0, 10)}.$format',
        ],
      ),
    );
  }
}
