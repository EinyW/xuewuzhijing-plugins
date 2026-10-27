import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/word.dart';

class DictionaryEntry {
  final int? id;
  final String source;
  final Word word;
  const DictionaryEntry({this.id, required this.source, required this.word});
}

/// 用户自己的离线词典；词典内容不自动进入收录本。
class DictionaryService {
  final _database = AppDatabase.instance;
  Future<int> _user() async =>
      (await SharedPreferences.getInstance()).getInt('user_id') ?? 1;

  Future<List<DictionaryEntry>> list({String keyword = ''}) async {
    final user = await _user();
    final term = keyword.trim();
    final rows = await _database.query(
      'dictionary_entries',
      where: term.isEmpty
          ? 'user_id = ?'
          : 'user_id = ? AND (word LIKE ? OR entry_json LIKE ?)',
      whereArgs: term.isEmpty ? [user] : [user, '%$term%', '%$term%'],
      orderBy: 'word COLLATE NOCASE ASC',
    );
    return rows
        .map(
          (row) => DictionaryEntry(
            id: row['id'] as int,
            source: row['source'] as String,
            word: Word.fromMap(
              Map<String, dynamic>.from(
                jsonDecode(row['entry_json'] as String),
              ),
            ),
          ),
        )
        .toList();
  }

  Future<void> put(Word word, {String source = '我的词典'}) async {
    if (word.word.trim().isEmpty) throw const FormatException('词条不能为空');
    final user = await _user();
    final db = await _database.database;
    await db.insert('dictionary_entries', {
      'user_id': user,
      'source': source.trim().isEmpty ? '我的词典' : source.trim(),
      'normalized': Word.normalizeWord(word.word),
      'word': word.word.trim(),
      'entry_json': jsonEncode(
        word.toMap()
          ..remove('id')
          ..remove('user_id'),
      ),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(int id) async {
    await _database.delete(
      'dictionary_entries',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, await _user()],
    );
  }

  Future<Map<String, dynamic>> exportData() async => {
    'format': 'xuewuzhijing.dictionary',
    'version': 1,
    'entries': [
      for (final entry in await list())
        {
          'source': entry.source,
          'word': entry.word.toMap()
            ..remove('id')
            ..remove('user_id'),
        },
    ],
  };

  Future<int> importData(Object? data) async {
    if (data is! Map ||
        data['format'] != 'xuewuzhijing.dictionary' ||
        data['version'] != 1 ||
        data['entries'] is! List) {
      throw const FormatException('不是受支持的词典文件');
    }
    final raw = data['entries'] as List;
    if (raw.length > 50000) throw const FormatException('单次最多导入 50000 个词条');
    final entries = <DictionaryEntry>[];
    for (final item in raw) {
      if (item is! Map || item['word'] is! Map)
        throw const FormatException('词典条目格式不正确');
      final source = item['source'];
      if (source != null && source is! String)
        throw const FormatException('词典名称格式不正确');
      final word = Word.fromMap(Map<String, dynamic>.from(item['word'] as Map));
      if (word.word.trim().isEmpty) throw const FormatException('词典中有空词条');
      entries.add(
        DictionaryEntry(
          source: source is String && source.trim().isNotEmpty
              ? source.trim()
              : '导入词典',
          word: word,
        ),
      );
    }
    final user = await _user();
    final db = await _database.database;
    await db.transaction((tx) async {
      for (final entry in entries) {
        final word = entry.word;
        await tx.insert('dictionary_entries', {
          'user_id': user,
          'source': entry.source,
          'normalized': Word.normalizeWord(word.word),
          'word': word.word.trim(),
          'entry_json': jsonEncode(
            word.toMap()
              ..remove('id')
              ..remove('user_id'),
          ),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    return entries.length;
  }
}
