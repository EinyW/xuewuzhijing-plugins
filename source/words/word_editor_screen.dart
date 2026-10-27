import 'package:flutter/material.dart';

import '../models/word.dart';
import '../services/word_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ipa_input_field.dart';
import 'dictionary_screen.dart';

/// 词语收录 / 编辑页
///
/// 表单按「词语 → 读音 → 词性 → 释义 → 例句 → 笔记标签」分段展示，
/// 每段有小标题与说明，长表单也不会看花眼。
class WordEditorScreen extends StatefulWidget {
  /// 传入表示编辑已有词条；为空表示新收录一个词。
  final Word? editing;

  /// 新收录时预填的词语（用于"查不到→马上收录"的场景）
  final String? initialWord;
  final bool dictionaryMode;

  const WordEditorScreen({
    super.key,
    this.editing,
    this.initialWord,
    this.dictionaryMode = false,
  });

  @override
  State<WordEditorScreen> createState() => _WordEditorScreenState();
}

class _WordEditorScreenState extends State<WordEditorScreen> {
  final _service = WordService();

  final _wordCtrl = TextEditingController();
  final _phoneticCtrl = TextEditingController();
  final _posCustomCtrl = TextEditingController();
  final _exampleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  /// 释义可自定义多条
  final List<TextEditingController> _defCtrls = [TextEditingController()];
  final List<String> _defParts = [''];
  List<String> _knownTags = [];

  /// 选中的词性（可多选）
  final Set<String> _partsOfSpeech = {};

  bool _saving = false;
  String? _error;

  /// 常见词性，点一下就能选 / 取消
  static const _posPresets = [
    'n.',
    'v.',
    'vt.',
    'vi.',
    'adj.',
    'adv.',
    'prep.',
    'conj.',
    'pron.',
    'num.',
    'art.',
    'int.',
    'phrase',
    'abbr.',
  ];

  @override
  void initState() {
    super.initState();
    _service.listTags().then((tags) {
      if (mounted) setState(() => _knownTags = tags);
    });
    final e = widget.editing;
    if (e != null) {
      _wordCtrl.text = e.word;
      _phoneticCtrl.text = e.phonetic ?? '';
      _exampleCtrl.text = e.example ?? '';
      _noteCtrl.text = e.note ?? '';
      _tagCtrl.text = e.tags.join(', ');
      _partsOfSpeech.addAll(e.partsOfSpeech);
      _defCtrls.clear();
      _defParts.clear();
      if (e.definitions.isEmpty) {
        _defCtrls.add(TextEditingController());
        _defParts.add('');
      } else {
        for (var i = 0; i < e.definitions.length; i++) {
          _defCtrls.add(TextEditingController(text: e.definitions[i]));
          _defParts.add(
            i < e.definitionParts.length ? e.definitionParts[i] : '',
          );
        }
      }
    } else if (widget.initialWord != null) {
      _wordCtrl.text = widget.initialWord!;
    }
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    _phoneticCtrl.dispose();
    _posCustomCtrl.dispose();
    _exampleCtrl.dispose();
    _noteCtrl.dispose();
    _tagCtrl.dispose();
    for (final c in _defCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _parseTags(String raw) {
    return raw
        .split(RegExp(r'[,，;；\s]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _fromDictionary() async {
    final word = await Navigator.push<Word>(
      context,
      MaterialPageRoute(
        builder: (_) => const DictionaryScreen(selectionMode: true),
      ),
    );
    if (word == null || !mounted) return;
    setState(() {
      _wordCtrl.text = word.word;
      _phoneticCtrl.text = word.phonetic ?? '';
      _exampleCtrl.text = word.example ?? '';
      _noteCtrl.text = word.note ?? '';
      _tagCtrl.text = word.tags.join(', ');
      _partsOfSpeech
        ..clear()
        ..addAll(word.partsOfSpeech);
      for (final controller in _defCtrls) {
        controller.dispose();
      }
      _defCtrls.clear();
      _defParts.clear();
      for (var i = 0; i < word.definitions.length; i++) {
        _defCtrls.add(TextEditingController(text: word.definitions[i]));
        _defParts.add(
          i < word.definitionParts.length ? word.definitionParts[i] : '',
        );
      }
      if (_defCtrls.isEmpty) {
        _defCtrls.add(TextEditingController());
        _defParts.add('');
      }
    });
  }

  String? _trimOrNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  /// 添加自定义词性
  void _addCustomPos() {
    final v = _posCustomCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _partsOfSpeech.add(v);
      _posCustomCtrl.clear();
    });
  }

  Future<void> _save() async {
    final rawWord = _wordCtrl.text.trim();
    if (rawWord.isEmpty) {
      setState(() => _error = '请填写要收录的词语');
      return;
    }

    final definitions = <String>[];
    final definitionParts = <String>[];
    for (var i = 0; i < _defCtrls.length; i++) {
      final text = _defCtrls[i].text.trim();
      if (text.isEmpty) continue;
      definitions.add(text);
      definitionParts.add(
        _partsOfSpeech.contains(_defParts[i]) ? _defParts[i] : '',
      );
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final word = Word(
        id: widget.editing?.id,
        word: rawWord,
        phonetic: _trimOrNull(_phoneticCtrl.text),
        partsOfSpeech: _partsOfSpeech.toList()..sort(),
        definitions: definitions,
        definitionParts: definitionParts,
        example: _trimOrNull(_exampleCtrl.text),
        note: _trimOrNull(_noteCtrl.text),
        tags: _parseTags(_tagCtrl.text),
        collectCount: widget.editing?.collectCount ?? 1,
        userId: widget.editing?.userId,
        isPinned: widget.editing?.isPinned ?? 0,
        lastCollectedAt: widget.editing?.lastCollectedAt,
        createdAt: widget.editing?.createdAt,
      );

      if (widget.dictionaryMode) {
        if (mounted) Navigator.pop(context, word);
        return;
      }
      String message;
      if (widget.editing == null) {
        // 新收录：已存在则次数 +1
        final result = await _service.collect(word);
        message = result.isNew
            ? '已收录「${result.word.word}」'
            : '「${result.word.word}」已在收录本中，收录次数 +1（共 ${result.collectCount} 次）';
      } else {
        await _service.updateWord(word);
        message = '已保存修改';
      }

      if (!mounted) return;
      Navigator.pop(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.dictionaryMode ? '编辑词典词条' : (isEditing ? '编辑词语' : '收录新词语'),
        ),
        actions: [
          if (!widget.dictionaryMode)
            IconButton(
              tooltip: '从词典填充',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: _fromDictionary,
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (isEditing)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: context.subtlePrimary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.repeat, size: 18, color: context.scheme.primary),
                  const SizedBox(width: 8),
                  Text('该词已被收录 ${widget.editing!.collectCount} 次'),
                ],
              ),
            ),

          // ---------------- 1. 词语 ----------------
          _sectionCard(
            index: 1,
            title: '词语',
            icon: Icons.text_fields,
            subtitle: '必填。重复收录同一个词只会累加收录次数',
            children: [
              TextField(
                controller: _wordCtrl,
                autofocus: !isEditing,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '词语',
                  hintText: '例如：ubiquitous',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),

          // ---------------- 2. 读音 ----------------
          _sectionCard(
            index: 2,
            title: '读音 / 音标',
            icon: Icons.record_voice_over_outlined,
            subtitle: '不确定音标怎么打？点右侧键盘图标，用音标符号面板输入',
            children: [IpaInputField(controller: _phoneticCtrl)],
          ),

          // ---------------- 3. 词性（可多选） ----------------
          _sectionCard(
            index: 3,
            title: '词性（可多选）',
            icon: Icons.category_outlined,
            subtitle: '一个词同时是名词和动词？把两个都选上',
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _posPresets.map((p) {
                  final selected = _partsOfSpeech.contains(p);
                  return FilterChip(
                    label: Text(p, style: const TextStyle(fontSize: 13)),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _partsOfSpeech.add(p);
                      } else {
                        _partsOfSpeech.remove(p);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _posCustomCtrl,
                      onSubmitted: (_) => _addCustomPos(),
                      decoration: const InputDecoration(
                        labelText: '其他词性（自己填）',
                        hintText: '如 aux. / 量词',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    tooltip: '添加',
                    onPressed: _addCustomPos,
                  ),
                ],
              ),
              if (_partsOfSpeech.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.subtlePrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 15,
                        color: context.scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '已选：${(_partsOfSpeech.toList()..sort()).join("、")}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _partsOfSpeech.clear()),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          // ---------------- 4. 释义 ----------------
          _sectionCard(
            index: 4,
            title: '释义',
            icon: Icons.format_list_numbered,
            subtitle: '可以写多条，会按 1、2、3 排列',
            children: [
              ..._defCtrls.asMap().entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.only(top: 12),
                        decoration: BoxDecoration(
                          color: context.subtleSurface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${e.key + 1}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: e.value,
                              maxLines: null,
                              minLines: 1,
                              decoration: InputDecoration(
                                hintText: e.key == 0
                                    ? '例如：无处不在的，普遍存在的'
                                    : '其他释义',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                'definition-part-${e.key}-${_partsOfSpeech.join('|')}',
                              ),
                              initialValue:
                                  _partsOfSpeech.contains(_defParts[e.key])
                                  ? _defParts[e.key]
                                  : '',
                              decoration: const InputDecoration(
                                labelText: '这条释义的词性',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('未指定'),
                                ),
                                for (final part
                                    in _partsOfSpeech.toList()..sort())
                                  DropdownMenuItem(
                                    value: part,
                                    child: Text(part),
                                  ),
                              ],
                              onChanged: (value) => setState(
                                () => _defParts[e.key] = value ?? '',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_defCtrls.length > 1)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: '删除此释义',
                          onPressed: () => setState(() {
                            _defCtrls[e.key].dispose();
                            _defCtrls.removeAt(e.key);
                            _defParts.removeAt(e.key);
                          }),
                        ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _defCtrls.add(TextEditingController());
                    _defParts.add('');
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('再加一条释义'),
                ),
              ),
            ],
          ),

          // ---------------- 5. 例句 ----------------
          _sectionCard(
            index: 5,
            title: '例句',
            icon: Icons.format_quote,
            subtitle: '选填，自己造一句记得更牢',
            children: [
              TextField(
                controller: _exampleCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Smartphones are ubiquitous in modern life.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),

          // ---------------- 6. 笔记与标签 ----------------
          _sectionCard(
            index: 6,
            title: '笔记与标签',
            icon: Icons.label_outline,
            subtitle: '选填，方便以后按标签筛选复习',
            children: [
              if (_knownTags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final tag in _knownTags)
                      ActionChip(
                        label: Text(tag),
                        onPressed: () {
                          final tags = _parseTags(_tagCtrl.text).toSet()
                            ..add(tag);
                          _tagCtrl.text = tags.join(', ');
                        },
                      ),
                  ],
                ),
              TextField(
                controller: _noteCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '我的笔记',
                  hintText: '记下自己的理解、易混词、使用场景…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tagCtrl,
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '多个标签用逗号分隔，如：考研, 阅读高频',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: context.scheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.scheme.error),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bookmark_add),
              label: Text(isEditing ? '保存修改' : '收录进我的收录本'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isEditing ? '提示：编辑不会改变收录次数。' : '提示：同一个词重复收录时会自动累加收录次数，不会产生重复条目。',
            style: TextStyle(fontSize: 11.5, color: context.faintText),
          ),
        ],
      ),
    );
  }

  /// 一个带序号的小节，把长表单切分成看得清的几块
  Widget _sectionCard({
    required int index,
    required String title,
    required IconData icon,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.subtlePrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: context.scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 17, color: context.mutedText),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: context.faintText),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
