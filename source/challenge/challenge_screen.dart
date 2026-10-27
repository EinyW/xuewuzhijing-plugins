import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/challenge_plan.dart';
import '../models/challenge_preset.dart';
import '../models/challenge_rules.dart';
import '../models/folder.dart';
import '../models/question.dart';
import '../services/challenge_service.dart';
import '../services/folder_service.dart';
import '../services/plugin_service.dart';
import '../services/points_service.dart';
import '../services/question_service.dart';
import '../widgets/start_quiz_button.dart';
import 'quiz_screen.dart';

class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  final _service = ChallengeService();
  final _name = TextEditingController(text: '我的挑战');
  final _fields = <String, TextEditingController>{};
  GlobalKey<FormState> _form = GlobalKey<FormState>();
  List<Question> _questions = [];
  List<Folder> _folders = [];
  List<ChallengePreset> _saved = [];
  final _selected = <int>{};
  ChallengeRules _rules = const ChallengeRules();
  ChallengeSelection _selection = ChallengeSelection.random;
  String? _presetId;
  int? _folderId;
  int _balance = 0;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _setFields(const ChallengePreset(id: '', name: '我的挑战'));
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setFields(ChallengePreset preset) {
    final values = {...preset.rules.toJson(), ...preset.counts};
    for (final entry in values.entries) {
      if (entry.value is! num) continue;
      (_fields[entry.key] ??= TextEditingController()).text = '${entry.value}';
    }
    _rules = preset.rules;
    _name.text = preset.name;
    _selection = preset.selection;
    _folderId = preset.folderId;
    _selected
      ..clear()
      ..addAll(preset.questionIds);
    _presetId = preset.id.isEmpty ? null : preset.id;
    _form = GlobalKey<FormState>();
  }

  Future<void> _load() async {
    try {
      final questions = await QuestionService().getVisibleQuestions();
      final folders = await FolderService().listFolders();
      final saved = await _service.list();
      final balance = PluginService.instance.pointsEnabled
          ? await PointsService.instance.totalPoints()
          : 0;
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _folders = folders;
        _saved = saved;
        _balance = balance;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('读取挑战配置失败：$e');
    }
  }

  List<Question> get _scoped {
    if (_folderId == null) return _questions;
    if (_folderId == -1) {
      return _questions.where((q) => q.folderId == null).toList();
    }
    final ids = <int>{_folderId!};
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in _folders) {
        if (ids.contains(f.parentId) && f.id != null && ids.add(f.id!)) {
          changed = true;
        }
      }
    }
    return _questions.where((q) => ids.contains(q.folderId)).toList();
  }

  Map<String, int> get _available => {
    for (final key in ChallengePreset.categories)
      key: _scoped.where((q) => ChallengePreset.categoryOf(q) == key).length,
  };

  int get _total => _selection == ChallengeSelection.manual
      ? _selected.length
      : ChallengePreset.categories.fold(
          0,
          (sum, key) => sum + (int.tryParse(_fields[key]!.text) ?? 0),
        );

  ChallengePreset? _read() {
    if (!(_form.currentState?.validate() ?? false)) return null;
    if (_total == 0) {
      _toast('请至少选择一道题目');
      return null;
    }
    if (_total > 10000) {
      _toast('单次挑战最多包含 10000 道题目');
      return null;
    }
    final rules = _rules.toJson();
    for (final key in ['entryCost', 'timeLimitSeconds', 'maxMistakes']) {
      rules[key] = int.parse(_fields[key]!.text);
    }
    for (final key in [
      'passPercent',
      'baseMultiplier',
      'comboBase',
      'comboCap',
    ]) {
      rules[key] = double.parse(_fields[key]!.text);
    }
    return ChallengePreset(
      id: _presetId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      rules: ChallengeRules.fromJson(rules),
      selection: _selection,
      folderId: _folderId,
      counts: {
        for (final key in ChallengePreset.categories)
          key: int.tryParse(_fields[key]!.text) ?? 0,
      },
      questionIds: _selected.toList(),
    );
  }

  Future<void> _save() async {
    final preset = _read();
    if (preset == null) return;
    try {
      await _service.save(preset);
      _presetId = preset.id;
      await _load();
      _toast('已保存「${preset.name}」');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    final preset = _read();
    if (preset == null) return;
    setState(() => _busy = true);
    try {
      final pool = preset.selection == ChallengeSelection.manual
          ? _questions
          : _scoped;
      final questions = _service.build(preset, pool);
      if (!PluginService.instance.pointsEnabled && preset.rules.entryCost > 0) {
        throw const FormatException('积分功能已关闭，请把入场消耗设为 0');
      }
      if (preset.rules.entryCost > 0 &&
          !await PointsService.instance.spend(
            preset.rules.entryCost,
            '挑战入场：${preset.name}',
          )) {
        throw const FormatException('积分不足，请降低入场消耗或先练习赚取积分');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizScreen(
            questions: questions,
            title: preset.name,
            challenge: true,
            challengeRules: preset.rules,
          ),
        ),
      );
      await _load();
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('无法开始挑战：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickQuestions() async {
    final ids = await Navigator.push<Set<int>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ChallengeQuestionPicker(questions: _scoped, selected: _selected),
      ),
    );
    if (ids != null && mounted) {
      setState(() {
        _selected
          ..clear()
          ..addAll(ids);
      });
    }
  }

  Future<void> _export(bool copy) async {
    final preset = _read();
    if (preset == null) return;
    try {
      final text = _service.export(preset, _questions);
      if (copy) {
        await Clipboard.setData(ClipboardData(text: text));
        _toast('分享配置已复制，可让其他用户粘贴导入');
      } else if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/challenge_${DateTime.now().millisecondsSinceEpoch}.json',
        );
        await file.writeAsString(text);
        await Share.shareXFiles([
          XFile(file.path, mimeType: 'application/json'),
        ], subject: preset.name);
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '导出挑战配置',
          fileName: 'challenge_${DateTime.now().millisecondsSinceEpoch}.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (path == null) return;
        await File(path).writeAsString(text);
        _toast('挑战配置已导出到 $path');
      }
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入挑战配置'),
        content: SizedBox(
          width: 580,
          child: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '粘贴其他用户分享的 JSON 配置，或选择文件',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                  withData: true,
                );
                if (result == null) return;
                final file = result.files.single;
                if (file.size > 20 * 1024 * 1024) {
                  throw const FormatException('分享文件超过 20 MB');
                }
                final content = file.bytes != null
                    ? utf8.decode(file.bytes!)
                    : await File(file.path!).readAsString();
                if (ctx.mounted) controller.text = content;
              } catch (e) {
                _toast('读取文件失败：$e');
              }
            },
            child: const Text('选择文件'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    try {
      final preset = await _service.import(text);
      if (!mounted) return;
      setState(() => _setFields(preset));
      await _load();
      _toast('已导入「${preset.name}」，题目和规则已就绪');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  void _classic() {
    final a = _available;
    final p = ChallengePlan.fromCounts(
      choiceAvailable: a['choice']!,
      multiAvailable: a['multi']!,
      fillAvailable: a['fill']!,
      longTextAvailable: a['long']!,
      materialAvailable: a['material']!,
    );
    setState(
      () => _setFields(
        ChallengePreset(
          id: '',
          name: '经典挑战',
          rules: const ChallengeRules(entryCost: 5000),
          folderId: _folderId,
          counts: {
            'choice': p.choice,
            'multi': p.multi,
            'fill': p.fill,
            'long': p.longText,
            'material': p.material,
          },
        ),
      ),
    );
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PluginService.instance.challengeEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('挑战工坊')),
        body: const Center(child: Text('请在插件中心启用挑战功能')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('挑战工坊'),
        actions: [
          IconButton(
            tooltip: '导入挑战',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_download_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '分享与预设',
            onSelected: (value) {
              switch (value) {
                case 'new':
                  setState(
                    () =>
                        _setFields(const ChallengePreset(id: '', name: '我的挑战')),
                  );
                case 'export':
                  _export(false);
                case 'copy':
                  _export(true);
                case 'classic':
                  _classic();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('新建挑战方案')),
              PopupMenuItem(value: 'export', child: Text('导出并分享配置')),
              PopupMenuItem(value: 'copy', child: Text('复制分享配置')),
              PopupMenuItem(value: 'classic', child: Text('使用经典挑战规则')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '把规则交给自己',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text('自选题目或按题型抽取，设置时间、通关条件与积分倍率。当前积分 $_balance 分。'),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _name,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: '挑战名称',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? '请填写挑战名称' : null,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final sections = [_selectionCard(), _rulesCard()];
                      return constraints.maxWidth > 900
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: sections[0]),
                                const SizedBox(width: 16),
                                Expanded(child: sections[1]),
                              ],
                            )
                          : Column(
                              children: [
                                sections[0],
                                const SizedBox(height: 16),
                                sections[1],
                              ],
                            );
                    },
                  ),
                  if (_saved.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      '我的挑战方案',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ..._saved.map(
                      (p) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.total} 题 · ${p.rules.timeLimitSeconds == 0 ? '不限时' : '${p.rules.timeLimitSeconds} 秒'} · 及格 ${p.rules.passPercent}%',
                          ),
                          onTap: _busy
                              ? null
                              : () => setState(() => _setFields(p)),
                          trailing: IconButton(
                            tooltip: '删除方案',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy
                                ? null
                                : () async {
                                    await _service.delete(p.id);
                                    await _load();
                                  },
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _loading || _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存方案'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StartQuizButton(
                  onPressed: _loading || _busy ? null : _start,
                  busy: _busy,
                  label: '开始答题（$_total 题）',
                  icon: Icons.local_fire_department_outlined,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _selectionCard() => _card('01  选择题目', [
    SegmentedButton<ChallengeSelection>(
      segments: const [
        ButtonSegment(
          value: ChallengeSelection.random,
          label: Text('按题型抽题'),
          icon: Icon(Icons.shuffle),
        ),
        ButtonSegment(
          value: ChallengeSelection.manual,
          label: Text('自选题目'),
          icon: Icon(Icons.checklist),
        ),
      ],
      selected: {_selection},
      onSelectionChanged: (v) => setState(() => _selection = v.first),
    ),
    const SizedBox(height: 16),
    DropdownButtonFormField<int>(
      key: ValueKey('folder-$_folderId-${_folders.length}'),
      initialValue: _folders.any((f) => f.id == _folderId) || _folderId == -1
          ? _folderId
          : 0,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '题目范围（包含子文件夹）',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: 0, child: Text('全部题库')),
        const DropdownMenuItem(value: -1, child: Text('未分类')),
        ..._folders.map(
          (f) => DropdownMenuItem(
            value: f.id,
            child: Text(f.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _folderId = v == 0 ? null : v),
    ),
    const SizedBox(height: 16),
    if (_selection == ChallengeSelection.manual) ...[
      Text('已选择 ${_selected.length} 题，当前范围 ${_scoped.length} 题。可切换范围继续添加。'),
      const SizedBox(height: 6),
      const Text('分享时会一并附带所选题目，接收者无需预先拥有相同题库。', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _pickQuestions,
        icon: const Icon(Icons.add_task),
        label: const Text('挑选题目'),
      ),
      if (_selected.isNotEmpty)
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: const Text('清空已选'),
        ),
    ] else ...[
      for (var i = 0; i < ChallengePreset.categories.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _number(
            ChallengePreset.categories[i],
            '${ChallengePreset.categoryNames[i]}（可用 ${_available[ChallengePreset.categories[i]]} 题）',
            0,
            10000,
            integer: true,
          ),
        ),
      TextButton.icon(
        onPressed: () => setState(() {
          final available = _available;
          for (final key in ChallengePreset.categories) {
            _fields[key]!.text = '${min(5, available[key]!)}';
          }
        }),
        icon: const Icon(Icons.auto_fix_high),
        label: const Text('按现有题量快速填入'),
      ),
      const Text(
        '分享此抽题方案时，接收者会按相同题型与数量从自己的题库中抽题。',
        style: TextStyle(fontSize: 12),
      ),
    ],
  ]);

  Widget _rulesCard() => _card('02  定义挑战规则', [
    LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 500
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 14,
          children:
              [
                    ('entryCost', '入场消耗（积分）', 0.0, 100000000.0, true),
                    ('timeLimitSeconds', '时限（秒，0 不限）', 0.0, 604800.0, true),
                    ('passPercent', '及格分数百分比', 0.0, 100.0, false),
                    ('maxMistakes', '错题终止数（0 不限）', 0.0, 10000.0, true),
                    ('baseMultiplier', '挑战积分基础倍率', 0.0, 100.0, false),
                    ('comboBase', '连对指数底数（1 关闭）', 1.0, 10.0, false),
                    ('comboCap', '连对倍率上限', 1.0, 100.0, false),
                  ]
                  .map(
                    (r) => SizedBox(
                      width: width,
                      child: _number(r.$1, r.$2, r.$3, r.$4, integer: r.$5),
                    ),
                  )
                  .toList(),
        );
      },
    ),
    const SizedBox(height: 12),
    _flag('shuffle', '打乱题目顺序', '每次开始使用新的顺序'),
    _flag('allowReview', '允许返回和回看', '关闭后不能返回已离开的题目'),
    _flag('allowSkip', '允许跳过题目', '未提交的题目按 0 分结算'),
    _flag('showFeedback', '作答时显示得分与解析', '关闭后在交卷结果中统一查看'),
    _flag('sessionBonus', '启用完美一局奖励', '全对时使用花式积分中的整局奖励'),
    const SizedBox(height: 6),
    const Text(
      '连对倍率 = 底数^(底数^连对数)，受上限限制。到达错题终止数或超时会自动交卷。',
      style: TextStyle(fontSize: 12),
    ),
  ]);

  Widget _number(
    String key,
    String label,
    num minValue,
    num maxValue, {
    bool integer = false,
  }) => TextFormField(
    controller: _fields[key],
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: (_) => setState(() {}),
    validator: (text) {
      final value = integer
          ? int.tryParse(text ?? '')
          : double.tryParse(text ?? '');
      return value == null ||
              !value.isFinite ||
              value < minValue ||
              value > maxValue
          ? '请输入 $minValue–$maxValue ${integer ? '的整数' : '的数值'}'
          : null;
    },
  );

  Widget _flag(String key, String title, String subtitle) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: _rules.toJson()[key] as bool,
    onChanged: (v) => setState(
      () => _rules = ChallengeRules.fromJson(_rules.toJson()..[key] = v),
    ),
  );
}

class _ChallengeQuestionPicker extends StatefulWidget {
  final List<Question> questions;
  final Set<int> selected;
  const _ChallengeQuestionPicker({
    required this.questions,
    required this.selected,
  });
  @override
  State<_ChallengeQuestionPicker> createState() =>
      _ChallengeQuestionPickerState();
}

class _ChallengeQuestionPickerState extends State<_ChallengeQuestionPicker> {
  late final Set<int> _selected = {...widget.selected};
  String _search = '';
  String? _type;

  List<Question> get _visible => widget.questions
      .where(
        (q) =>
            (_type == null || ChallengePreset.categoryOf(q) == _type) &&
            q.stem.toLowerCase().contains(_search.toLowerCase()),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final all =
        visible.isNotEmpty && visible.every((q) => _selected.contains(q.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('挑选挑战题目'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              for (final q in visible) {
                all ? _selected.remove(q.id) : _selected.add(q.id!);
              }
            }),
            child: Text(all ? '取消当前全选' : '全选当前结果'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索题干',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('全部题型'),
                  selected: _type == null,
                  onSelected: (_) => setState(() => _type = null),
                ),
                for (var i = 0; i < ChallengePreset.categories.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(ChallengePreset.categoryNames[i]),
                      selected: _type == ChallengePreset.categories[i],
                      onSelected: (_) =>
                          setState(() => _type = ChallengePreset.categories[i]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('当前范围内没有符合条件的题目'))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, index) {
                      final q = visible[index];
                      return CheckboxListTile(
                        value: _selected.contains(q.id),
                        title: Text(
                          q.stem,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${q.type.displayName} · ${q.totalScore} 分',
                        ),
                        onChanged: (v) => setState(() {
                          v == true
                              ? _selected.add(q.id!)
                              : _selected.remove(q.id);
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, _selected),
            icon: const Icon(Icons.check),
            label: Text('使用已选 ${_selected.length} 道题'),
          ),
        ),
      ),
    );
  }
}
