import 'package:flutter_test/flutter_test.dart';
import 'package:nspire_notes/note.dart';

void main() {
  test('JSON backup round trip preserves note fields', () {
    final note = Note(title: 'Встреча', content: 'Итоги', category: 'Совещание',
      eventAt: DateTime(2026, 11, 9, 10, 30), updatedAt: DateTime(2026, 11, 9, 11), pinned: true);
    final parsed = deserializeNotes(serializeNotes([note]));
    expect(parsed.length, 1);
    expect(parsed.single.title, 'Встреча');
    expect(parsed.single.eventAt.hour, 10);
    expect(parsed.single.pinned, true);
  });
  test('Rejects unsupported backups', () {
    expect(() => deserializeNotes('{"notes":[]}'), throwsFormatException);
  });
}
