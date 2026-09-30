import 'package:flutter_test/flutter_test.dart';
import 'package:workmate/attendance/domain/description_chips.dart';

void main() {
  test('tapping a chip on an empty box fills it', () => expect(toggleDescriptionChip('', 'Masonry'), 'Masonry'));
  test('a second chip is added, not substituted',
      () => expect(toggleDescriptionChip('Masonry', 'Concrete pouring'), 'Masonry, Concrete pouring'));
  test('tapping a chip that is already there removes it',
      () => expect(toggleDescriptionChip('Masonry, Concrete pouring', 'Masonry'), 'Concrete pouring'));
  test('removing the only chip empties the box', () => expect(toggleDescriptionChip('Masonry', 'Masonry'), ''));
  test('typed text survives a chip being added',
      () => expect(toggleDescriptionChip('Gate 2, may delivery', 'Masonry'), 'Gate 2, may delivery, Masonry'));
  test('typed text survives a chip being removed',
      () => expect(toggleDescriptionChip('Gate 2, may delivery, Masonry', 'Masonry'), 'Gate 2, may delivery'));

  test('a newline stays inside its part instead of splitting it', () {
    const typed = 'Gate 2\nmay delivery';
    expect(descriptionParts(typed), [typed]);
    expect(toggleDescriptionChip(typed, 'Masonry'), '$typed, Masonry');
  });

  test('a chip already typed by hand is not duplicated', () {
    expect(isChipSelected('masonry', 'Masonry'), isTrue);
    expect(toggleDescriptionChip('masonry', 'Masonry'), '');
  });

  test('selection only matches a whole part', () {
    expect(isChipSelected('Masonry work', 'Masonry'), isFalse);
    expect(toggleDescriptionChip('Masonry work', 'Masonry'), 'Masonry work, Masonry');
  });

  test('stray separators do not become empty parts', () {
    expect(descriptionParts('Masonry, , '), ['Masonry']);
    expect(toggleDescriptionChip('Masonry, , ', 'Masonry'), '');
  });
}
