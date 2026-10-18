import 'dart:io';
import '../lib/matrix_font.dart';
import '../lib/w2_program.dart';

List<bool> matrix(String text) {
  final pixels = List.filled(512, false);
  final width = text
      .split('')
      .fold<int>(-1, (n, c) => n + glyphs[c]!.split('/').first.length + 1);
  var left = (32 - width) ~/ 2;
  for (final char in text.split('')) {
    final rows = glyphs[char]!.split('/');
    for (var y = 0; y < 7; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        if (rows[y][x] == '1') {
          pixels[(1 + y * 2) * 32 + left + x] = true;
          pixels[(2 + y * 2) * 32 + left + x] = true;
        }
      }
    }
    left += rows.first.length + 1;
  }
  return pixels;
}

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Specify output directory.');
  final directory = arguments.single;
  File(
    '$directory/paused.bin',
  ).writeAsBytesSync(W2Program.frames([matrix('01:50')]));
  File(
    '$directory/cue.bin',
  ).writeAsBytesSync(W2Program.frames([matrix('AMEN')]));
  stdout.writeln('Generated static Matrix pause and cue programs.');
}
