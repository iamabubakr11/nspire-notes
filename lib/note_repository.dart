import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'note.dart';

class NoteRepository {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(p.join(dir.path, 'nspire_notes.db'), version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            category TEXT NOT NULL,
            event_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0
          )
        ''');
      });
    _database = db;
    return db;
  }

  Future<List<Note>> all() async {
    final db = await database;
    final rows = await db.query('notes', orderBy: 'pinned DESC, event_at DESC, id DESC');
    return rows.map(Note.fromDatabase).toList();
  }

  Future<void> save(Note note) async {
    final db = await database;
    if (note.id == null) {
      await db.insert('notes', note.toDatabase());
    } else {
      await db.update('notes', note.toDatabase(), where: 'id = ?', whereArgs: [note.id]);
    }
  }

  Future<void> delete(int id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> importMany(List<Note> notes) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final note in notes) {
        await txn.insert('notes', note.toDatabase());
      }
    });
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
