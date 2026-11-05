import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/reports/service_pdf.dart';

Future<void> main(List<String> args) async {
  final out = Directory(args.single)..createSync(recursive: true);
  final regular = ByteData.sublistView(
    File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync(),
  );
  final bold = ByteData.sublistView(
    File('assets/fonts/Roboto-Bold.ttf').readAsBytesSync(),
  );
  final banner = base64Encode(
    File('test/fixtures/church-banner.png').readAsBytesSync(),
  );
  final segments = [
    for (var i = 0; i < 36; i++)
      Segment(
        'Service segment ${i + 1}',
        5,
        speaker: 'Speaker ${i + 1}',
        notes: i == 5
            ? List.filled(30, 'PRIVATE NOTE ONLY FOR THE OPERATOR.').join(' ')
            : 'PRIVATE NOTE ${i + 1}',
      ),
  ];
  final program = Timeline(
    'Youth Sunday — Thanksgiving Service',
    segments,
    DisplaySettings(),
  );
  final date = DateTime(2026, 10, 18, 9).millisecondsSinceEpoch;
  final prepared = DateTime(2026, 10, 20, 14, 30).millisecondsSinceEpoch;
  final report = ServiceReport(
    'print-review',
    program.name,
    date,
    date + 10800000,
    10800000,
    1,
    false,
    [for (final s in segments) ReportRow(s.name, 300000, 290000, 10000, 0)],
    churchName: 'Glory Arena Church',
    program: program,
  );
  for (final mode in ['operator', 'stage', 'ink']) {
    final data = ServicePrintDocument(
      program: program,
      report: report,
      fullReport: mode != 'stage',
      church: report.churchName,
      serviceDate: date,
      preparedAt: prepared,
      banner: banner,
      includeNotes: mode == 'operator',
      watermark: true,
      inkSaving: mode == 'ink',
      audience: mode == 'operator' ? 'operator' : 'stage',
    );
    final bytes = await createServicePdf(
      data,
      regularFont: regular,
      boldFont: bold,
    );
    File('${out.path}/service-$mode.pdf').writeAsBytesSync(bytes);
    stdout.writeln('$mode: ${bytes.length} bytes');
  }
}
