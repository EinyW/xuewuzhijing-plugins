import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models/whiteboard.dart';
import 'package:learning_plugin_sdk/learning_plugin_sdk.dart';

class WhiteboardService {
  static final incomingQuestion = ValueNotifier<Question?>(null);
  Future<String> get _storageKey async {
    final prefs = await SharedPreferences.getInstance();
    return 'whiteboard_v1_${prefs.getInt('user_id') ?? 'local'}';
  }

  Future<WhiteboardDocument> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _storageKey);
    if (raw == null) return const WhiteboardDocument();
    return WhiteboardDocument.fromJson(jsonDecode(raw));
  }

  Future<void> save(WhiteboardDocument document) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(await _storageKey, jsonEncode(document.toJson()));
    if (!ok) throw const FileSystemException('画板保存失败');
  }

  /// Keep file-picker temporary files available after the next app launch.
  Future<String> importFile(String source) async {
    final file = File(source);
    if (await file.length() > 100 * 1024 * 1024) {
      throw const FormatException('单份资料不能超过 100 MB');
    }
    final base = await getApplicationDocumentsDirectory();
    final prefs = await SharedPreferences.getInstance();
    final folder = Directory(p.join(base.path, 'whiteboard',
        '${prefs.getInt('user_id') ?? 'local'}', 'materials'));
    await folder.create(recursive: true);
    if (p.isWithin(folder.path, source)) return source;
    final destination = p.join(folder.path,
        '${DateTime.now().microsecondsSinceEpoch}_${p.basename(source)}');
    return (await file.copy(destination)).path;
  }

  static String docxText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) throw const FormatException('此 DOCX 缺少正文');
    if (entry.size > 15 * 1024 * 1024) {
      throw const FormatException('DOCX 正文过大，请使用外部应用查看');
    }
    final xml = XmlDocument.parse(utf8.decode(entry.content));
    return xml.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'p')
        .map((paragraph) => paragraph.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 't')
            .map((element) => element.innerText)
            .join())
        .where((text) => text.trim().isNotEmpty)
        .join('\n\n');
  }
}
