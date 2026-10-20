import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'domain.dart';

/// A frozen print snapshot. Historical data comes only from the stored report.
class ServicePrintDocument {
  final Timeline program;
  final ServiceReport? report;
  final String church, banner, audience;
  final bool includeNotes, includeBanner, watermark, inkSaving, fullReport;
  final int serviceDate, preparedAt;
  const ServicePrintDocument({
    required this.program,
    required this.church,
    required this.serviceDate,
    required this.preparedAt,
    this.report,
    this.banner = '',
    this.audience = 'stage',
    this.includeNotes = false,
    this.includeBanner = true,
    this.watermark = true,
    this.inkSaving = false,
    this.fullReport = false,
  });
}

Future<Uint8List> createServicePdf(
  ServicePrintDocument data, {
  required ByteData regularFont,
  required ByteData boldFont,
  double width = 595.28,
  double height = 841.89,
}) async {
  final regular = pw.Font.ttf(regularFont), bold = pw.Font.ttf(boldFont);
  final ink = PdfColor.fromHex('#172c25'), muted = PdfColor.fromHex('#53645d');
  final accent = data.inkSaving ? PdfColors.black : PdfColor.fromHex('#214e48');
  final doc = pw.Document(
    title: data.program.name,
    author: data.church,
    creator: 'Church Service Timer · I-Proton',
  );
  final pageWidth = width.clamp(360.0, 1800.0);
  final pageHeight = height.clamp(500.0, 2200.0);
  final full = data.fullReport && data.report != null;
  final rows = <List<String>>[];
  final program = data.program;
  final total = program.segments.fold<int>(0, (n, s) => n + s.minutes);
  final rowCount = full ? data.report!.rows.length : program.segments.length;
  for (var i = 0; i < rowCount; i++) {
    final segment = i < program.segments.length ? program.segments[i] : null;
    final recorded = full ? data.report!.rows[i] : null;
    final name = recorded?.name ?? segment!.name;
    final description = [
      name,
      if (segment != null && segment.speaker.isNotEmpty) segment.speaker,
      if (data.includeNotes && segment != null && segment.notes.isNotEmpty)
        'Private: ${segment.notes}',
    ].join('\n');
    // Bounded chunks let very long private notes span pages without an oversized row.
    final chunks = <String>[];
    var remainder = description;
    while (remainder.runes.length > 430) {
      final chars = remainder.runes.toList();
      var split = chars.take(430).toList().lastIndexOf(32);
      if (split < 200) split = 400;
      chunks.add(String.fromCharCodes(chars.take(split)));
      remainder = String.fromCharCodes(chars.skip(split)).trimLeft();
    }
    chunks.add(remainder);
    for (var part = 0; part < chunks.length; part++) {
      rows.add([
        part == 0 ? '${i + 1}' : '',
        part == 0 ? chunks[part] : '(continued)\n${chunks[part]}',
        part > 0
            ? ''
            : recorded == null
            ? '${segment!.minutes} min'
            : durationLabel(recorded.plannedMs),
        if (full)
          part > 0
              ? ''
              : recorded!.actualMs == null
              ? 'Not completed'
              : durationLabel(recorded.actualMs!),
        if (full) part > 0 ? '' : durationLabel(recorded!.pausedMs),
      ]);
    }
  }
  pw.Widget title({bool white = false}) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (data.church.isNotEmpty)
        pw.Text(
          data.church,
          style: pw.TextStyle(
            fontSize: 12,
            color: white ? PdfColors.white : muted,
          ),
        ),
      pw.SizedBox(height: 6),
      pw.Text(
        program.name,
        style: pw.TextStyle(
          font: bold,
          fontSize: 24,
          color: white ? PdfColors.white : ink,
        ),
      ),
    ],
  );
  final theme = pw.PageTheme(
    pageFormat: PdfPageFormat(pageWidth, pageHeight),
    margin: const pw.EdgeInsets.fromLTRB(42, 38, 42, 34),
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    buildBackground: data.watermark && !data.inkSaving && data.church.isNotEmpty
        ? (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: math.pi * 35 / 180,
                child: pw.Opacity(
                  opacity: .07,
                  child: pw.SizedBox(
                    width: pageWidth * .9,
                    height: 100,
                    child: pw.FittedBox(
                      child: pw.Text(
                        data.church,
                        style: pw.TextStyle(font: bold, fontSize: 64),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        : null,
  );
  doc.addPage(
    pw.MultiPage(
      pageTheme: theme,
      maxPages: 500,
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                '${program.name} · ${serviceDateLabel(data.serviceDate)}',
                style: pw.TextStyle(fontSize: 9, color: muted),
              ),
            ),
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400, width: .5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Church Service Timer · I-Proton',
              style: pw.TextStyle(fontSize: 9, color: muted),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: muted),
            ),
          ],
        ),
      ),
      build: (_) => [
        if (data.includeBanner && !data.inkSaving)
          pw.Container(
            height: 160,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.ClipRRect(
              horizontalRadius: 12,
              verticalRadius: 12,
              child: pw.Stack(
                children: [
                  if (data.banner.isNotEmpty)
                    pw.Positioned.fill(
                      child: pw.Image(
                        pw.MemoryImage(base64Decode(data.banner)),
                        fit: pw.BoxFit.cover,
                      ),
                    ),
                  pw.Positioned.fill(
                    child: pw.Opacity(
                      opacity: .48,
                      child: pw.Container(color: PdfColors.black),
                    ),
                  ),
                  pw.Positioned(
                    left: 20,
                    right: 20,
                    bottom: 18,
                    child: title(white: true),
                  ),
                ],
              ),
            ),
          )
        else
          title(),
        pw.SizedBox(height: 18),
        pw.Text(
          'Service date · ${serviceDateLabel(data.serviceDate)}',
          style: pw.TextStyle(font: bold, fontSize: 12, color: accent),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Prepared: ${preparedDateLabel(data.preparedAt)}',
          style: pw.TextStyle(fontSize: 9, color: muted),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '${full ? (data.report!.rehearsal ? 'Rehearsal report' : 'Service report') : 'Service rundown'} · $total minutes · ${data.includeNotes
              ? 'Operator copy — private notes included'
              : data.audience == 'operator'
              ? 'Operator copy — private notes excluded'
              : 'Stage copy — private notes excluded'}',
          style: pw.TextStyle(fontSize: 10, color: muted),
        ),
        if (full)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Total recorded: ${data.report!.totalMs == null ? 'Unavailable' : durationLabel(data.report!.totalMs!)}${data.report!.uncertain ? ' · Timing uncertain' : ''}',
              style: pw.TextStyle(fontSize: 10),
            ),
          ),
        if (data.report != null && data.report!.program == null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Older record: speaker names and private notes were not recorded.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        pw.SizedBox(height: 14),
        pw.Table(
          columnWidths: {
            0: const pw.FixedColumnWidth(34),
            1: const pw.FlexColumnWidth(4),
            2: const pw.FlexColumnWidth(),
            if (full) 3: const pw.FlexColumnWidth(),
            if (full) 4: const pw.FlexColumnWidth(),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(
                color: data.inkSaving
                    ? PdfColors.grey200
                    : PdfColor.fromHex('#e9f0ec'),
              ),
              children: [
                for (final label in [
                  '#',
                  'Segment / speaker',
                  full ? 'Planned' : 'Duration',
                  if (full) 'Actual',
                  if (full) 'Paused',
                ])
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(7),
                    child: pw.Text(
                      label,
                      style: pw.TextStyle(font: bold, fontSize: 9),
                    ),
                  ),
              ],
            ),
            for (final row in rows)
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: .4),
                  ),
                ),
                children: [
                  for (final cell in row)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 9,
                      ),
                      child: pw.Text(
                        cell,
                        style: pw.TextStyle(fontSize: 10, color: ink),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
