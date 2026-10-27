import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/word.dart';
import '../services/config_transfer_service.dart';
import '../services/dictionary_service.dart';
import 'word_editor_screen.dart';

class DictionaryScreen extends StatefulWidget {
  final bool selectionMode;
  const DictionaryScreen({super.key, this.selectionMode = false});
  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final _service = DictionaryService();
  final _search = TextEditingController();
  List<DictionaryEntry> _entries = [];
  bool _loading = true;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final entries = await _service.list(keyword: _search.text);
    if (mounted && request == _request)
      setState(() {
        _entries = entries;
        _loading = false;
      });
  }

  void _toast(String value) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _edit([DictionaryEntry? entry]) async {
    final word = await Navigator.push<Word>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            WordEditorScreen(editing: entry?.word, dictionaryMode: true),
      ),
    );
    if (word == null) return;
    try {
      await _service.put(word, source: entry?.source ?? '我的词典');
      if (entry != null &&
          Word.normalizeWord(entry.word.word) !=
              Word.normalizeWord(word.word)) {
        await _service.remove(entry.id!);
      }
      await _load();
      _toast('已保存到词典');
    } catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _import() async {
    try {
      final text = await ConfigTransferService.readJson(
        maxBytes: 20 * 1024 * 1024,
      );
      if (text == null) return;
      final count = await _service.importData(jsonDecode(text));
      await _load();
      _toast('已导入 $count 个词条');
    } catch (error) {
      _toast('导入失败：$error');
    }
  }

  Future<void> _export() async {
    try {
      final result = await ConfigTransferService.writeJson(
        '学习词典.json',
        await _service.exportData(),
      );
      if (result != null) _toast('词典已导出');
    } catch (error) {
      _toast('导出失败：$error');
    }
  }

  Future<void> _remove(DictionaryEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除词典中的「${entry.word.word}」？'),
        content: const Text('收录本中已有的词语不会受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.remove(entry.id!);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.selectionMode ? '选择词典词条' : '我的词典'),
      actions: [
        IconButton(
          tooltip: '导入词典',
          onPressed: _import,
          icon: const Icon(Icons.file_open_outlined),
        ),
        IconButton(
          tooltip: '导出词典',
          onPressed: _export,
          icon: const Icon(Icons.ios_share),
        ),
        IconButton(
          tooltip: '添加词条',
          onPressed: _edit,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            onChanged: (_) => _load(),
            decoration: const InputDecoration(
              labelText: '搜索词语或释义',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
              ? const Center(child: Text('词典暂无匹配词条，可添加或导入词典'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (_, index) {
                    final entry = _entries[index];
                    final word = entry.word;
                    return ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(
                        '${word.word}${word.phonetic == null ? '' : '  ${word.phonetic}'}',
                      ),
                      subtitle: Text(
                        '${word.primaryDefinition}\n${entry.source}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      onTap: widget.selectionMode
                          ? () => Navigator.pop(context, word)
                          : () => _edit(entry),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(entry);
                          if (v == 'delete') _remove(entry);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('编辑词条')),
                          PopupMenuItem(value: 'delete', child: Text('删除词条')),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
