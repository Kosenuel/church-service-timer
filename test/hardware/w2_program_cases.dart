import 'dart:typed_data';
import 'package:church_service_timer/hardware/w2_program.dart';
import '../domain/feature_cases.dart' show equal;

final w2ProgramCases = <String, void Function()>{
  'W2 frames preserve row order, corners, and autonomous frame metadata': () {
    final first = List.filled(512, false);
    for (final index in [0, 31, 480, 511]) {
      first[index] = true;
    }
    final second = List.filled(512, false)..[33] = true;
    final staticBytes = W2Program.frames([first]);
    equal(staticBytes.length, 233);
    equal(staticBytes[142], 0x30);
    equal(staticBytes[169], 128);
    equal(staticBytes[172], 1);
    equal(staticBytes[229], 128);
    equal(staticBytes[232], 1);
    final bytes = W2Program.frames([first, second]);
    final b = ByteData.sublistView(bytes);
    equal(bytes.length, 299);
    equal(b.getUint16(143), 2);
    equal(b.getUint32(155), 31);
    equal(b.getUint16(164), 50);
    equal(bytes[166], 0);
    equal(bytes[171 + 64 + 4], 64);
  },
  'W2 countdown follows container offsets without hardware configuration': () {
    final bytes = W2Program.countdown(
      0x12345678,
      programId: List.filled(16, 7),
    );
    final data = ByteData.sublistView(bytes);
    equal(bytes.length, 393);
    equal(String.fromCharCodes(bytes.sublist(0, 2)), 'HC');
    equal(data.getUint16(3), 1);
    equal(data.getUint32(19), 0);
    final program = data.getUint32(27);
    equal(String.fromCharCodes(bytes.sublist(program, program + 2)), 'HP');
    equal(data.getUint16(program + 2), 59);
    equal(bytes[program + 5], 0);
    equal(bytes[program + 17], 0);
    final area = program + data.getUint32(program + 60);
    equal(String.fromCharCodes(bytes.sublist(area, area + 2)), 'HA');
    equal(data.getUint16(area + 8), 32);
    equal(data.getUint16(area + 10), 16);
    final timer = area + data.getUint32(area + 37);
    equal(bytes[timer + 2], 0x34);
    equal(bytes[timer + 3], 3);
    equal(data.getUint32(timer + 4), 0x12345678);
    equal(bytes.sublist(timer + 4, timer + 8).join(','), '18,52,86,120');
    equal(bytes[timer + 12], 13);
    equal(bytes[timer + 13], 0);
    equal(bytes[timer + 55], 0);
    equal(area + data.getUint32(timer + 33), timer + 57);
  },
  'Original Matrix zero and colon retain their exact pixels on hardware': () {
    final bytes = W2Program.countdown(1);
    equal(
      bytes.sublist(197, 211).join(','),
      '112,112,136,136,152,152,168,168,200,200,136,136,112,112',
    );
    equal(
      bytes.sublist(337, 351).join(','),
      '0,0,128,128,128,128,0,0,128,128,128,128,0,0',
    );
    equal(bytes.sublist(379).every((b) => b == 0), true);
    final data = ByteData.sublistView(bytes);
    equal(data.getUint16(165), 2);
  },
  'W2 encoder rejects invalid target and program identity': () {
    for (final target in [-1, 0x100000000]) {
      var rejected = false;
      try {
        W2Program.countdown(target);
      } on ArgumentError {
        rejected = true;
      }
      equal(rejected, true);
    }
    for (final id in [<int>[], List.filled(16, 256), List.filled(16, -1)]) {
      var rejected = false;
      try {
        W2Program.countdown(0, programId: id);
      } on ArgumentError {
        rejected = true;
      }
      equal(rejected, true);
    }
  },
};
