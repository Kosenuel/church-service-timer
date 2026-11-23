import 'package:church_service_timer/domain/bible_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('number words and filler become plain digits', () {
    for (final (input, expected) in [
      // Numbers.
      ('psalm twenty three', 'psalm 23'),
      ('psalm twenty-three', 'psalm 23'),
      ('john three sixteen', 'john 3 16'),
      ('romans eight twenty-eight', 'romans 8 28'),
      ('genesis one one', 'genesis 1 1'),
      ('psalm one hundred nineteen', 'psalm 119'),
      ('psalm one hundred and nineteen', 'psalm 119'),
      ('psalm a hundred nineteen', 'psalm 119'),
      ('psalm a hundred and nineteen', 'psalm 119'),
      ('psalm hundred and nineteen', 'psalm 119'),
      ('psalm one hundred', 'psalm 100'),
      ('psalm one hundred fifty', 'psalm 150'),
      (
        'psalm one hundred and nineteen verse one hundred seventy six',
        'psalm 119:176',
      ),
      (
        'psalm one hundred nineteen verse one hundred and seventy-six',
        'psalm 119:176',
      ),
      ('psalm one hundred and one', 'psalm 101'),
      ('john three zero', 'john 3 0'),
      ('john ninety nine', 'john 99'),
      ('john forty two', 'john 42'),
      ('john thirteen', 'john 13'),
      ('john ten', 'john 10'),
      // Chapter and verse words.
      ('john chapter 3 verse 16', 'john 3:16'),
      ('john chapter three verse sixteen', 'john 3:16'),
      ('john chapter three, verse sixteen', 'john 3:16'),
      ('john 3 verses 16 to 18', 'john 3:16-18'),
      (
        'first corinthians chapter thirteen verses four to seven',
        'first corinthians 13:4-7',
      ),
      ('john 3 vs 9', 'john 3:9'),
      ('john 3 v 9', 'john 3:9'),
      ('john 3v9', 'john 3:9'),
      ('john3v9', 'john 3:9'),
      ('john3 v9-11', 'john 3:9-11'),
      ('John 3 verse 9', 'john 3:9'),
      ('john 3 vs. 9', 'john 3:9'),
      ('john three colon sixteen', 'john 3:16'),
      // Ranges.
      ('john 3 16 to 18', 'john 3 16-18'),
      ('john 3:16 through 18', 'john 3:16-18'),
      ('john 3:16 thru 18', 'john 3:16-18'),
      ('john 3:16 until 18', 'john 3:16-18'),
      ('john 3:16 - 18', 'john 3:16-18'),
      ('john 3:16–18', 'john 3:16-18'),
      ('john 3:16—18', 'john 3:16-18'),
      ('john 3:16 - 4:2', 'john 3:16-4:2'),
      ('john 3 16 and 17', 'john 3 16&17'),
      ('john three sixteen and seventeen', 'john 3 16&17'),
      ('psalm 120 to 122', 'psalm 120-122'),
      // Filler.
      ('the book of john chapter 3', 'john 3'),
      ('turn to john 3 16', 'john 3 16'),
      (
        'turn with me to the book of john chapter three verse sixteen',
        'john 3:16',
      ),
      ('please open your bible to john 3', 'john 3'),
      ('in john 3:16', 'john 3:16'),
      ('let us read john 3 16', 'john 3 16'),
      ('the gospel according to john 3:16', 'john 3:16'),
      ('read from first kings chapter three', 'first kings 3'),
      // Already numeric input comes back tidied.
      ('John 3:9', 'john 3:9'),
      ('John 3 9', 'john 3 9'),
      ('Joh3: 9', 'joh 3:9'),
      ('jn 3.9', 'jn 3:9'),
      ('jn 3,9', 'jn 3:9'),
      ('1cor13 4-7', '1 cor 13 4-7'),
      ('  John   3 : 16  ', 'john 3:16'),
      ('1st Corinthians 13:4', 'first corinthians 13:4'),
      ('2nd Peter 1:3', 'second peter 1:3'),
      ('3rd John 4', 'third john 4'),
      ('Song of Solomon 2:1', 'song of solomon 2:1'),
      ('one john four eight', '1 john 4 8'),
      ('two timothy three sixteen', '2 timothy 3 16'),
    ]) {
      test('"$input"', () {
        expect(normaliseSpokenReference(input), expected);
      });
    }
  });

  test('"ch" and "of" inside a book name are left alone', () {
    expect(normaliseSpokenReference('1 ch 3'), '1 ch 3');
    expect(normaliseSpokenReference('song of songs 2'), 'song of songs 2');
  });

  test('every number from 1 to 176 reads back from words', () {
    const ones = [
      '', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
      'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
      'sixteen', 'seventeen', 'eighteen', 'nineteen', //
    ];
    const tens = [
      '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
      'eighty', 'ninety', //
    ];
    String words(int n, {required String hundred}) {
      final parts = <String>[];
      if (n >= 100) {
        parts.add(hundred);
        n %= 100;
      }
      if (n >= 20) {
        parts.add(tens[n ~/ 10]);
        if (n % 10 > 0) parts.add(ones[n % 10]);
      } else if (n > 0) {
        parts.add(ones[n]);
      }
      return parts.join(' ');
    }

    for (var n = 1; n <= 176; n++) {
      for (final h in ['one hundred', 'a hundred', 'one hundred and']) {
        if (h.endsWith('and') && n % 100 == 0) continue;
        if (n < 100 && h != 'one hundred') continue;
        expect(
          normaliseSpokenReference('psalm ${words(n, hundred: h)}'),
          'psalm $n',
          reason: '$n as "${words(n, hundred: h)}"',
        );
      }
    }
  });
}
