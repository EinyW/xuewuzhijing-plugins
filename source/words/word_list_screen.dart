import 'package:flutter/material.dart';

import '../widgets/start_quiz_button.dart';
import 'dictionary_screen.dart';
import '../theme/app_theme.dart';
import '../models/word.dart';
import '../services/word_service.dart';
import 'word_editor_screen.dart';
import 'word_test_screen.dart';

/// 查看收录内容
///
/// 支持自定义排序（例如按某个词的收录次数升序/降序）、搜索、置顶、编辑、删除。
class WordListScreen extends StatefulWidget {
  const WordListScreen({super.key});

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen> {
  final _service = WordService();
  final _searchCtrl = TextEditingController();

  List<Word> _words = [];
  Map<String, int> _stats = {'count': 0, 'total': 0};
  WordSort _sort = WordSort.collectCountDesc;
  String _keyword = '';
  String? _tagFilter;
  WordCountFilter _countFilter = WordCountFilter.all;
  List<String> _allTags = [];
  bool _loading = true;

  bool get _hasFilter =>
      _tagFilter != null || _countFilter != WordCountFilter.all;

  // 多选
  bool _multiSelect = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.listWords(
      sort: _sort,
      keyword: _keyword,
      tag: _tagFilter,
      countFilter: _countFilter,
    );
    final stats = await _service.stats();
    final tags = await _service.listTags();
    if (!mounted) return;
    setState(() {
      _words = list;
      _stats = stats;
      _allTags = tags;
      _loading = false;
    });
  }

  Future<void> _addWord() async {
    final msg = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const WordEditorScreen()),
    );
    if (!mounted) return;
    await _load();
    if (msg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _editWord(Word w) async {
    final msg = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => WordEditorScreen(editing: w)),
    );
    if (!mounted) return;
    await _load();
    if (msg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _collectAgain(Word w) async {
    final updated = await _service.collectAgain(w.id!);
    if (!mounted) return;
    await _load();
    if (updated != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '「${updated.word}」收录次数 +1（共 ${updated.collectCount} 次）',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _togglePin(Word w) async {
    await _service.togglePin(w.id!);
    _load();
  }

  Future<void> _deleteWord(Word w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定从收录本中删除「${w.word}」吗？\n（已收录 ${w.collectCount} 次）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && w.id != null) {
      await _service.deleteWord(w.id!);
      _load();
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 ${_selectedIds.length} 个词语？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.deleteMany(_selectedIds.toList());
      _exitMultiSelect();
      _load();
    }
  }

  /// 手动调整收录次数
  Future<void> _editCollectCount(Word w) async {
    final ctrl = TextEditingController(text: '${w.collectCount}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('调整「${w.word}」的收录次数'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '收录次数',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final v = int.tryParse(ctrl.text.trim());
    ctrl.dispose();
    if (ok == true && v != null && w.id != null) {
      await _service.setCollectCount(w.id!, v);
      _load();
    }
  }

  void _enterMultiSelect(int id) {
    setState(() {
      _multiSelect = true;
      _selectedIds.add(id);
    });
  }

  void _exitMultiSelect() {
    setState(() {
      _multiSelect = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _multiSelect = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _pickSort() async {
    final result = await showModalBottomSheet<_WordFilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WordFilterSheet(
        sort: _sort,
        tag: _tagFilter,
        countFilter: _countFilter,
        allTags: _allTags,
      ),
    );
    if (result == null) return;
    setState(() {
      _sort = result.sort;
      _tagFilter = result.tag;
      _countFilter = result.countFilter;
    });
    _load();
  }

  /// 展示某个词的完整信息 + 收录流水
  Future<void> _showDetail(Word w) async {
    final logs = await _service.collectLogs(w.id!);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    w.word,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (w.isPinned == 1)
                  const Icon(Icons.push_pin, color: Colors.blue),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (w.phonetic != null && w.phonetic!.isNotEmpty)
                  Chip(
                    label: Text(w.phonetic!),
                    visualDensity: VisualDensity.compact,
                  ),
                if (w.partsOfSpeech.isNotEmpty)
                  Chip(
                    label: Text(w.partOfSpeechLabel),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: context.isDark
                        ? const Color(0xFF1E3A24)
                        : Colors.green[50],
                  ),
                Chip(
                  label: Text('收录 ${w.collectCount} 次'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: context.subtleWarning,
                ),
              ],
            ),
            const Divider(height: 24),

            if (w.definitions.isNotEmpty) ...[
              const Text('释义', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...w.definitions.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${e.key + 1}. ${e.key < w.definitionParts.length && w.definitionParts[e.key].isNotEmpty ? '${w.definitionParts[e.key]} ' : ''}${e.value}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (w.example != null && w.example!.isNotEmpty) ...[
              const Text('例句', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.subtleSurface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(w.example!),
              ),
              const SizedBox(height: 12),
            ],

            if (w.note != null && w.note!.isNotEmpty) ...[
              const Text('我的笔记', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(w.note!),
              const SizedBox(height: 12),
            ],

            if (w.tags.isNotEmpty) ...[
              const Text('标签', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: w.tags
                    .map(
                      (t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],

            Text(
              '首次收录：${_formatTime(w.createdAt)}'
              '${w.lastCollectedAt != null ? '\n最近收录：${_formatTime(w.lastCollectedAt!)}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 24),

            Text(
              '收录流水（${logs.length} 条）',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (logs.isEmpty)
              const Text(
                '暂无流水记录',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              )
            else
              ...logs
                  .take(20)
                  .map(
                    (l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.circle, size: 6, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(l.collectedAt),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _collectAgain(w);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('再收录一次'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editWord(w);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('编辑内容'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final d = DateTime.parse(iso);
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}-${two(d.month)}-${two(d.day)} '
          '${two(d.hour)}:${two(d.minute)}';
    } catch (_) {
      return iso;
    }
  }

  /// 开始测试：选方向和数量，随机抽当前列表里的词
  Future<void> _startTest() async {
    final usable = _words.where((w) => w.definitions.isNotEmpty).toList();
    if (usable.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少需要 2 个有释义的词语才能测试')));
      return;
    }

    var direction = WordTestDirection.wordToMeaning;
    var count = usable.length >= 10 ? 10 : usable.length;

    final picked = await showDialog<({int count, WordTestDirection direction})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('词语测试'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '从当前列表（${usable.length} 个有释义的词）里抽题。',
                style: TextStyle(fontSize: 12, color: ctx.mutedText),
              ),
              const SizedBox(height: 12),
              const Text(
                '测试方向',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: WordTestDirection.values
                    .map(
                      (d) => ChoiceChip(
                        label: Text(
                          d.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: direction == d,
                        onSelected: (_) => setDialogState(() => direction = d),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              const Text(
                '测试数量',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final n in {5, 10, 20, usable.length})
                    if (n <= usable.length)
                      ChoiceChip(
                        label: Text(
                          n == usable.length ? '全部（$n）' : '$n',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: count == n,
                        onSelected: (_) => setDialogState(() => count = n),
                      ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, (count: count, direction: direction)),
              child: const Text('开始'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final pool = List<Word>.of(usable)..shuffle();
    final selected = pool.take(picked.count).toList();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            WordTestScreen(words: selected, direction: picked.direction),
      ),
    );
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _words.isNotEmpty && _selectedIds.length == _words.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_multiSelect ? '已选 ${_selectedIds.length} 项' : '我的收录本'),
        leading: _multiSelect
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitMultiSelect,
              )
            : null,
        actions: _multiSelect
            ? [
                TextButton(
                  onPressed: _words.isEmpty
                      ? null
                      : () => setState(() {
                          if (allSelected) {
                            _selectedIds.clear();
                          } else {
                            _selectedIds
                              ..clear()
                              ..addAll(_words.map((w) => w.id!));
                          }
                        }),
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: '删除',
                  onPressed: _batchDelete,
                ),
              ]
            : [
                IconButton(
                  tooltip: '搜索词典',
                  icon: const Icon(Icons.menu_book_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DictionaryScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.quiz_outlined),
                  tooltip: '开始测试',
                  onPressed: _startTest,
                ),
                IconButton(
                  icon: const Icon(Icons.sort),
                  tooltip: '排序方式',
                  onPressed: _pickSort,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '收录新词语',
                  onPressed: _addWord,
                ),
              ],
      ),
      body: Column(
        children: [
          // 统计条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: context.subtlePrimary,
            child: Row(
              children: [
                const Icon(Icons.menu_book, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  '共 ${_stats['count']} 个词语 · 累计收录 ${_stats['total']} 次',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),

          // 搜索
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _keyword = v;
                _load();
              },
              decoration: InputDecoration(
                hintText: '搜索词语 / 释义 / 笔记 / 标签',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _keyword = '';
                          _load();
                        },
                      ),
              ),
            ),
          ),

          // 当前筛选/排序提示（点击可改）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: InkWell(
              onTap: _pickSort,
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt,
                    size: 14,
                    color: _hasFilter ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _filterSummary(),
                      style: TextStyle(
                        fontSize: 12,
                        color: _hasFilter
                            ? context.scheme.primary
                            : context.faintText,
                        fontWeight: _hasFilter ? FontWeight.w600 : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.swap_vert, size: 14, color: Colors.grey),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      _sort.displayName,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  if (_hasFilter)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _tagFilter = null;
                          _countFilter = WordCountFilter.all;
                        });
                        _load();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '清除筛选',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                    ),
                  const Text(
                    '设置',
                    style: TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),
          const Divider(height: 1),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _words.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 56,
                          color: context.faintText,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _keyword.isEmpty
                              ? '收录本还是空的\n点右上角 + 收录第一个词语'
                              : '没有找到匹配「$_keyword」的词语',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _words.length,
                    itemBuilder: (_, i) => _buildItem(_words[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _multiSelect
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: StartQuizButton(
                  onPressed: _loading || _words.length < 2 ? null : _startTest,
                  label: '开始答题 · 词语测试',
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addWord,
        icon: const Icon(Icons.add),
        label: const Text('收录词语'),
      ),
    );
  }

  Widget _buildItem(Word w) {
    final pinned = w.isPinned == 1;
    final selected = _selectedIds.contains(w.id);

    if (_multiSelect) {
      return CheckboxListTile(
        value: selected,
        onChanged: (_) => _toggleSelect(w.id!),
        title: Text(w.word),
        subtitle: Text(
          w.primaryDefinition,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        secondary: _countBadge(w.collectCount),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: _countBadge(w.collectCount),
        title: Row(
          children: [
            if (pinned)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.push_pin, size: 16, color: Colors.blue),
              ),
            Flexible(
              child: Text(
                w.word,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (w.phonetic != null && w.phonetic!.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  w.phonetic!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (w.partsOfSpeech.isNotEmpty)
              Text(
                w.partOfSpeechLabel,
                style: const TextStyle(fontSize: 11, color: Colors.green),
              ),
            Text(
              w.primaryDefinition,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (w.tags.isNotEmpty)
              Text(
                w.tags.map((t) => '#$t').join(' '),
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        isThreeLine: true,
        onTap: () => _showDetail(w),
        onLongPress: () {
          if (w.id != null) _enterMultiSelect(w.id!);
        },
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'collect':
                _collectAgain(w);
                break;
              case 'edit':
                _editWord(w);
                break;
              case 'count':
                _editCollectCount(w);
                break;
              case 'pin':
                _togglePin(w);
                break;
              case 'delete':
                _deleteWord(w);
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'collect', child: Text('再收录一次')),
            const PopupMenuItem(value: 'edit', child: Text('编辑内容')),
            const PopupMenuItem(value: 'count', child: Text('调整收录次数')),
            PopupMenuItem(value: 'pin', child: Text(pinned ? '取消置顶' : '置顶')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  /// 收录次数徽标
  Widget _countBadge(int count) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: count >= 3 ? context.badgeHighlight : context.badgeNormal,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: count >= 3
                  ? (context.isDark ? Colors.orange[300] : Colors.deepOrange)
                  : context.scheme.primary,
            ),
          ),
          const Text('次', style: TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  /// 当前筛选的简短描述
  String _filterSummary() {
    final parts = <String>[];
    if (_tagFilter != null) parts.add('#$_tagFilter');
    if (_countFilter != WordCountFilter.all) {
      parts.add(_countFilter.displayName);
    }
    if (parts.isEmpty) return '筛选：全部';
    return '筛选：${parts.join(' · ')}';
  }
}

/// 词语列表的筛选 + 排序结果
class _WordFilterResult {
  final WordSort sort;
  final String? tag;
  final WordCountFilter countFilter;

  const _WordFilterResult({
    required this.sort,
    required this.tag,
    required this.countFilter,
  });
}

/// 词语列表的筛选 + 排序面板
class _WordFilterSheet extends StatefulWidget {
  final WordSort sort;
  final String? tag;
  final WordCountFilter countFilter;
  final List<String> allTags;

  const _WordFilterSheet({
    required this.sort,
    required this.tag,
    required this.countFilter,
    required this.allTags,
  });

  @override
  State<_WordFilterSheet> createState() => _WordFilterSheetState();
}

class _WordFilterSheetState extends State<_WordFilterSheet> {
  late WordSort _sort;
  String? _tag;
  late WordCountFilter _countFilter;

  @override
  void initState() {
    super.initState();
    _sort = widget.sort;
    _tag = widget.tag;
    _countFilter = widget.countFilter;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text(
                    '筛选与排序',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _tag = null;
                      _countFilter = WordCountFilter.all;
                      _sort = WordSort.collectCountDesc;
                    }),
                    child: const Text('重置'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  // ---------- 标签筛选 ----------
                  const Text(
                    '标签筛选',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  if (widget.allTags.isEmpty)
                    const Text(
                      '还没有给词语打过标签',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        FilterChip(
                          label: const Text('全部标签'),
                          selected: _tag == null,
                          onSelected: (_) => setState(() => _tag = null),
                        ),
                        ...widget.allTags.map(
                          (t) => FilterChip(
                            label: Text('#$t'),
                            selected: _tag == t,
                            onSelected: (v) =>
                                setState(() => _tag = v ? t : null),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 20),

                  // ---------- 收录次数筛选 ----------
                  const Text(
                    '收录次数',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  RadioGroup<WordCountFilter>(
                    groupValue: _countFilter,
                    onChanged: (v) => setState(() => _countFilter = v!),
                    child: Column(
                      children: WordCountFilter.values.map((c) {
                        return RadioListTile<WordCountFilter>(
                          value: c,
                          title: Text(c.displayName),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ---------- 排序 ----------
                  const Text(
                    '排序方式',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  RadioGroup<WordSort>(
                    groupValue: _sort,
                    onChanged: (v) => setState(() => _sort = v!),
                    child: Column(
                      children: WordSort.values.map((s) {
                        return RadioListTile<WordSort>(
                          value: s,
                          title: Text(s.displayName),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  onPressed: () => Navigator.pop(
                    context,
                    _WordFilterResult(
                      sort: _sort,
                      tag: _tag,
                      countFilter: _countFilter,
                    ),
                  ),
                  label: const Text('应用'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
