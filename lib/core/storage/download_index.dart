import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../data/models/invite.dart';

class DownloadIndex {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'musicbyadi_downloads.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE downloads (
            song_id       TEXT PRIMARY KEY,
            local_path    TEXT NOT NULL,
            size_bytes    INTEGER NOT NULL,
            downloaded_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<String?> pathFor(String songId) async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      columns: ['local_path'],
      where: 'song_id = ?',
      whereArgs: [songId],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      final path = maps.first['local_path'] as String;
      if (await File(path).exists()) {
        return path;
      } else {
        // Stale record, file removed
        await remove(songId);
      }
    }
    return null;
  }

  Future<void> recordDownload(DownloadedTrack track) async {
    final db = await database;
    await db.insert(
      'downloads',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(String songId) async {
    final db = await database;
    final maps = await db.query(
      'downloads',
      columns: ['local_path'],
      where: 'song_id = ?',
      whereArgs: [songId],
    );
    if (maps.isNotEmpty) {
      final path = maps.first['local_path'] as String;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await db.delete('downloads', where: 'song_id = ?', whereArgs: [songId]);
  }

  Future<List<DownloadedTrack>> getAll() async {
    final db = await database;
    final results = await db.query('downloads', orderBy: 'downloaded_at DESC');
    return results.map((m) => DownloadedTrack.fromMap(m)).toList();
  }

  Future<int> getTotalStorageUsed() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COALESCE(SUM(size_bytes), 0) as total FROM downloads');
    return (result.first['total'] as int?) ?? 0;
  }

  Future<void> clearAll() async {
    final all = await getAll();
    for (final item in all) {
      final file = File(item.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    final db = await database;
    await db.delete('downloads');
  }
}
