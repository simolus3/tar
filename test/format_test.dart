import 'package:tar/tar.dart';
import 'package:test/test.dart';

void main() {
  test('operator |', () {
    expect(TarFormat.gnu | TarFormat.star, _isFormat('GNU or STAR'));
    expect(TarFormat.star | TarFormat.gnu, _isFormat('GNU or STAR'));

    expect(TarFormat.v7 | TarFormat.pax | TarFormat.star,
        _isFormat('V7 or PAX or STAR'));
  });

  test('has', () {
    expect(TarFormat.gnu.has(TarFormat.gnu), isTrue);
    expect(TarFormat.gnu.has(TarFormat.v7), isFalse);

    expect(TarFormat.gnu.has(TarFormat.v7 | TarFormat.gnu), isFalse);
    expect((TarFormat.v7 | TarFormat.gnu).has(TarFormat.gnu), isTrue);
  });

  test('mayOnlyBe', () {
    expect(TarFormat.gnu.mayOnlyBe(TarFormat.v7), _isInvalid);
    expect(TarFormat.gnu.mayOnlyBe(TarFormat.gnu), TarFormat.gnu);

    expect((TarFormat.gnu | TarFormat.pax).mayOnlyBe(TarFormat.pax),
        TarFormat.pax);
    expect(
      (TarFormat.gnu | TarFormat.pax | TarFormat.v7)
          .mayOnlyBe(TarFormat.pax | TarFormat.v7),
      _isFormat('V7 or PAX'),
    );
    expect((TarFormat.gnu | TarFormat.pax).mayOnlyBe(TarFormat.v7), _isInvalid);
  });
}

TypeMatcher<MaybeTarFormat> _isFormat(String representation) {
  return isA<MaybeTarFormat>()
      .having((e) => e.description, 'description', representation);
}

TypeMatcher<MaybeTarFormat> get _isInvalid {
  return _isFormat('Invalid').having((e) => e.valid, 'valid', isFalse);
}
