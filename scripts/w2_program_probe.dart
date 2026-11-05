import 'dart:io';
import 'package:church_service_timer/w2_program.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Specify output file.');
  // Target is set from the phone clock immediately before the controlled test.
  final bytes = W2Program.countdown(0);
  File(arguments.single).writeAsBytesSync(bytes);
  stdout.writeln('Generated ${bytes.length}-byte Matrix countdown program.');
}
