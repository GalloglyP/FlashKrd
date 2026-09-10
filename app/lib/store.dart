import 'dart:convert';
import 'dart:io';

import 'package:flashkrd/models.dart';
import 'package:fsrs/fsrs.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class Store {
  Store();

  Database? _db;
  late final Directory _docs;

  Database get db => _db!;

  Future<void> open() async {
    _docs = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(_docs.path, 'flashkrd.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE decks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            rev INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            deck_id TEXT NOT NULL,
            front TEXT NOT NULL,
            back TEXT NOT NULL,
            extra TEXT NOT NULL,
            tags TEXT NOT NULL,
            sort_index INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cards (
            note_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            due TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE files (
            id TEXT PRIMARY KEY,
            deck_id TEXT NOT NULL,
            path TEXT NOT NULL,
            sha256 TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX notes_deck_id ON notes (deck_id)');
        await db.execute('CREATE INDEX cards_due ON cards (due)');
      },
    );
  }

  Directory mediaDir(String deckId) {
    return Directory(p.join(_docs.path, 'media', deckId));
  }

  File mediaFile(String deckId, String relPath) {
    return File(p.join(mediaDir(deckId).path, relPath));
  }

  Future<List<Deck>> decks() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await db.rawQuery('''
      SELECT d.id, d.title, d.description, d.rev,
             (SELECT COUNT(*) FROM cards c
               JOIN notes n ON n.id = c.note_id
              WHERE n.deck_id = d.id AND c.due <= ?) AS due_count
      FROM decks d
      ORDER BY d.title
    ''', [now]);
    return [
      for (final row in rows)
        Deck(
          id: row['id'] as String,
          title: row['title'] as String,
          description: row['description'] as String,
          rev: row['rev'] as int,
          dueCount: row['due_count'] as int,
        ),
    ];
  }

  Future<int?> deckRev(String id) async {
    final rows = await db.query('decks', columns: ['rev'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['rev'] as int;
  }

  Future<List<Note>> dueNotes({String? deckId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = deckId == null
        ? await db.rawQuery('''
            SELECT n.* FROM notes n
            JOIN cards c ON c.note_id = n.id
            WHERE c.due <= ?
            ORDER BY c.due, n.sort_index, n.id
          ''', [now])
        : await db.rawQuery('''
            SELECT n.* FROM notes n
            JOIN cards c ON c.note_id = n.id
            WHERE n.deck_id = ? AND c.due <= ?
            ORDER BY c.due, n.sort_index, n.id
          ''', [deckId, now]);
    return rows.map(_noteFromRow).toList();
  }

  Future<Card> cardFor(String noteId) async {
    final rows = await db.query('cards', where: 'note_id = ?', whereArgs: [noteId]);
    if (rows.isEmpty) {
      return Card(cardId: noteId.hashCode);
    }
    final map = jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
    return Card.fromMap(map);
  }

  Future<void> saveCard(String noteId, Card card) async {
    await db.insert('cards', {
      'note_id': noteId,
      'payload': jsonEncode(card.toMap()),
      'due': card.due.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> fileSha(String id) async {
    final rows = await db.query('files', columns: ['sha256'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['sha256'] as String;
  }

  Future<void> applyDeck(Map<String, dynamic> payload) async {
    final id = payload['id'] as String;
    final notes = (payload['notes'] as List).cast<Map<String, dynamic>>();
    final files = (payload['files'] as List).cast<Map<String, dynamic>>();
    await db.transaction((txn) async {
      await txn.insert('decks', {
        'id': id,
        'title': payload['title'],
        'description': payload['description'] ?? '',
        'rev': payload['rev'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      for (final note in notes) {
        final noteId = note['id'] as String;
        if (note['deleted_at'] != null) {
          await txn.delete('notes', where: 'id = ?', whereArgs: [noteId]);
          await txn.delete('cards', where: 'note_id = ?', whereArgs: [noteId]);
          continue;
        }
        await txn.insert('notes', {
          'id': noteId,
          'deck_id': note['deck_id'],
          'front': note['front'] ?? '',
          'back': note['back'] ?? '',
          'extra': note['extra'] ?? '',
          'tags': jsonEncode(note['tags'] ?? []),
          'sort_index': note['sort_index'] ?? 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        final existing = await txn.query('cards', where: 'note_id = ?', whereArgs: [noteId]);
        if (existing.isEmpty) {
          final card = Card(cardId: noteId.hashCode);
          await txn.insert('cards', {
            'note_id': noteId,
            'payload': jsonEncode(card.toMap()),
            'due': card.due.toUtc().toIso8601String(),
          });
        }
      }
      for (final file in files) {
        final fileId = file['id'] as String;
        if (file['deleted_at'] != null) {
          await txn.delete('files', where: 'id = ?', whereArgs: [fileId]);
          continue;
        }
        await txn.insert('files', {
          'id': fileId,
          'deck_id': file['deck_id'],
          'path': file['path'],
          'sha256': file['sha256'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Note _noteFromRow(Map<String, Object?> row) {
    final tagsRaw = row['tags'] as String;
    List<String> tags = const [];
    try {
      tags = (jsonDecode(tagsRaw) as List).cast<String>();
    } catch (_) {}
    return Note(
      id: row['id'] as String,
      deckId: row['deck_id'] as String,
      front: row['front'] as String,
      back: row['back'] as String,
      extra: row['extra'] as String,
      tags: tags,
      sortIndex: row['sort_index'] as int,
    );
  }
}
