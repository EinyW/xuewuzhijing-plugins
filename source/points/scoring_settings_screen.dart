import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/points.dart';
import '../models/question.dart';
import '../models/scoring_profile.dart';
import '../services/scoring_service.dart';
import '../widgets/points_burst.dart';

/// 花样积分的独立入口：规则、基础分、弹层外观以及方案分享。
class ScoringSettingsScreen extends StatefulWidget {
  const ScoringSettingsScreen({super.key});

  @override
  State<ScoringSettingsScreen> createState() => _ScoringSettingsScreenState();
}

class _ScoringSettingsScreenState extends State<ScoringSettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _previewKey = GlobalKey();
  final _fields = <String, TextEditingController>{};
  ScoringProfile _profile = const ScoringProfile();
  bool _loading = true;
  VoidCallback? _removePreview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ScoringService.instance.load();
    if (!mounted) return;
    _hydrate(ScoringService.instance.profile.value);
    setState(() => _loading = false);
  }

  void _hydrate(ScoringProfile value) {
    _profile = value;
    final values = <String, String>{
      'name': value.name,
      'multiplier': '${value.multiplier}',
      'cap': '${value.questionCap}',
      'fontSize': '${value.fontSize}',
      'detailFontSize': '${value.detailFontSize}',
      'displayMs': '${value.displayMs}',
      'color': value.colorValue.toRadixString(16).padLeft(8, '0').toUpperCase(),
      'sessionMinimum': '${value.sessionMinimum}',
      'sessionBonus': '${value.sessionBonus}',
      'sessionPerQuestion': '${value.sessionPerQuestion}',
      'sessionLabel': value.sessionLabel,
      for (final range in value.baseRanges.entries) ...{
        '${range.key}.min': '${range.value.$1}',
        '${range.key}.max': '${range.value.$2}',
      },
    };
    for (final entry in values.entries) {
      (_fields[entry.key] ??= TextEditingController()).text = entry.value;
    }
  }

  @override
  void dispose() {
    _removePreview?.call();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _text(String key) => _fields[key]!.text.trim();
  int _int(String key) => int.parse(_text(key));
  double _double(String key) => double.parse(_text(key));

  ScoringProfile? _read() {
    if (!(_form.currentState?.validate() ?? false)) return null;
    try {
      final color = _text('color').replaceFirst('#', '');
      final value = _profile.copyWith(
        name: _text('name'),
        multiplier: _double('multiplier'),
        questionCap: _int('cap'),
        baseRanges: {
          for (final key in ScoringProfile.defaultRanges.keys)
            key: (_int('$key.min'), _int('$key.max')),
        },
        colorValue: int.parse(
          color.length == 6 ? 'FF$color' : color,
          radix: 16,
        ),
        fontSize: _double('fontSize'),
        detailFontSize: _double('detailFontSize'),
        displayMs: _int('displayMs'),
        sessionMinimum: _int('sessionMinimum'),
        sessionBonus: _int('sessionBonus'),
        sessionPerQuestion: _int('sessionPerQuestion'),
        sessionLabel: _text('sessionLabel'),
      );
      value.validate();
      return value;
    } on FormatException catch (e) {
      _message(e.message);
      return null;
    }
  }

  Future<void> _save() async {
    final value = _read();
    if (value == null) return;
    try {
      await ScoringService.instance.save(value);
      _message('积分方案已保存，下一次答题立即使用');
    } catch (e) {
      _message('保存失败：$e');
    }
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('无法读取所选文件');
      final profile = ScoringService.instance.decode(utf8.decode(bytes));
      if (!mounted) return;
      setState(() => _hydrate(profile));
      _message('方案已载入，可预览和编辑，点击保存后应用');
    } catch (e) {
      _message('导入失败：$e');
    }
  }

  Future<void> _export({bool share = false}) async {
    final value = _read();
    if (value == null) return;
    try {
      final raw = ScoringService.instance.encode(value);
      final bytes = Uint8List.fromList(utf8.encode(raw));
      final name = 'scoring_${DateTime.now().millisecondsSinceEpoch}.json';
      if (share) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        await file.writeAsBytes(bytes);
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/json')],
          subject: '花样积分 · ${value.name}',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '导出积分方案',
          fileName: name,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );
        if (path == null) return;
        if (!Platform.isAndroid && !Platform.isIOS) {
          await File(path).writeAsBytes(bytes);
        }
        _message('积分方案已导出，可由其他用户导入');
      }
    } catch (e) {
      _message('导出失败：$e');
    }
  }

  Future<void> _exchangeText() async {
    final value = _read();
    if (value == null) return;
    final controller = TextEditingController(
      text: ScoringService.instance.encode(value),
    );
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('复制或粘贴方案'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: '积分方案 JSON',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: controller.text));
              _message('方案已复制');
            },
            child: const Text('复制全部'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('载入文本'),
          ),
        ],
      ),
    );
    if (raw != null && mounted) {
      try {
        final imported = ScoringService.instance.decode(raw);
        setState(() => _hydrate(imported));
        _message('方案已载入，点击保存后应用');
      } catch (e) {
        _message('载入失败：$e');
      }
    }
    // Dialog 的关闭动画结束后才释放输入控制器。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  void _preview() {
    final value = _read();
    if (value == null) return;
    _removePreview?.call();
    _removePreview = showPointsBurst(
      context: context,
      anchorKey: _previewKey,
      profile: value.copyWith(showPopup: true),
      award: PointsAward(
        points: 1280,
        basePoints: 100,
        multiplier: value.multiplier * 2,
        bonusPoints: 0,
        hits: value.rules
            .where((r) => r.enabled)
            .take(3)
            .map(
              (r) => PointsHit(
                label: r.name,
                multiplier: r.multiplier,
                bonus: r.bonus,
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _editRule([int? index]) async {
    final original = index == null
        ? ScoringRule(
            id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
            name: '自定义得分',
          )
        : _profile.rules[index];
    final result = await showDialog<ScoringRule>(
      context: context,
      builder: (_) => _RuleEditor(rule: original),
    );
    if (result == null || !mounted) return;
    final rules = [..._profile.rules];
    if (index == null) {
      rules.add(result);
    } else {
      rules[index] = result;
    }
    setState(() => _profile = _profile.copyWith(rules: rules));
  }

  Widget _field(
    String key,
    String label, {
    bool number = false,
    bool decimal = false,
    String? hint,
  }) => TextFormField(
    controller: _fields[key],
    decoration: InputDecoration(
      labelText: label,
      helperText: hint,
      border: const OutlineInputBorder(),
    ),
    keyboardType: number
        ? TextInputType.numberWithOptions(decimal: decimal)
        : TextInputType.text,
    validator: (value) {
      final raw = value?.trim() ?? '';
      if (raw.isEmpty) return '请填写$label';
      if (number) {
        final numeric = decimal ? double.tryParse(raw) : int.tryParse(raw);
        if (numeric == null || !numeric.isFinite || numeric < 0) {
          return '请输入有效的非负${decimal ? '数值' : '整数'}';
        }
      }
      if (key == 'color' &&
          !RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(raw)) {
        return '填写 6 位 RGB 或 8 位 ARGB 色值';
      }
      return null;
    },
  );

  Widget _grid(List<Widget> children, {double minWidth = 220}) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / minWidth).floor().clamp(1, 3);
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 16,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );

  Widget _section(String title, String subtitle, Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 22),
          child,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('花样积分'),
      actions: [
        TextButton.icon(
          onPressed: _loading ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('保存'),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _form,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '让每一次进步，都有自己的得分方式',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text('调整后点击保存即可应用到答题、挑战和词语测试。方案可以通过文件或文本分享。'),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _import,
                            icon: const Icon(Icons.file_open_outlined),
                            label: const Text('导入方案'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _export(),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('导出文件'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _export(share: true),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('分享方案'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _exchangeText,
                            icon: const Icon(Icons.code),
                            label: const Text('复制 / 粘贴'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _hydrate(const ScoringProfile()));
                              _message('已载入默认方案，点击保存后应用');
                            },
                            child: const Text('恢复默认'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _section(
                        '基础计分',
                        '按题目实际得分比例计算基础分，再叠加倍率与固定奖励。',
                        _grid([
                          _field('name', '方案名称'),
                          _field(
                            'multiplier',
                            '全局倍率（0～1000）',
                            number: true,
                            decimal: true,
                          ),
                          _field('cap', '每题积分上限（1～1 亿）', number: true),
                          for (final key in ScoringProfile.rangeNames.keys)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _field(
                                    '$key.min',
                                    '${ScoringProfile.rangeNames[key]}最低分',
                                    number: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _field(
                                    '$key.max',
                                    '最高分',
                                    number: true,
                                  ),
                                ),
                              ],
                            ),
                        ], minWidth: 290),
                      ),
                      _section(
                        '得分弹层',
                        '设置弹出得分的颜色、字号与显示时间，预览使用当前未保存的参数。',
                        Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('显示得分弹层'),
                              value: _profile.showPopup,
                              onChanged: (v) => setState(
                                () =>
                                    _profile = _profile.copyWith(showPopup: v),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _grid([
                              _field(
                                'color',
                                '颜色（RGB / ARGB）',
                                hint: '例如 FFB74D 或 FFFFB74D',
                              ),
                              _field(
                                'fontSize',
                                '得分字号（12～96）',
                                number: true,
                                decimal: true,
                              ),
                              _field(
                                'detailFontSize',
                                '规则字号（8～48）',
                                number: true,
                                decimal: true,
                              ),
                              _field(
                                'displayMs',
                                '显示时间（300～60000 毫秒）',
                                number: true,
                              ),
                            ]),
                            const SizedBox(height: 18),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                key: _previewKey,
                                onPressed: _preview,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('预览得分弹层'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _section(
                        '花式得分规则',
                        '编辑名称、倍率、额外积分与触发条件。同一互斥组只应用一条：速度组选最短时限，其他组选最高连击门槛。',
                        Column(
                          children: [
                            for (var i = 0; i < _profile.rules.length; i++)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Switch(
                                  value: _profile.rules[i].enabled,
                                  onChanged: (enabled) {
                                    final json = _profile.rules[i].toJson()
                                      ..['enabled'] = enabled;
                                    final rules = [..._profile.rules]
                                      ..[i] = ScoringRule.fromJson(json);
                                    setState(
                                      () => _profile = _profile.copyWith(
                                        rules: rules,
                                      ),
                                    );
                                  },
                                ),
                                title: Text(_profile.rules[i].name),
                                subtitle: Text(
                                  '×${_profile.rules[i].multiplier}  +${_profile.rules[i].bonus}  · ${_conditionSummary(_profile.rules[i])}',
                                ),
                                onTap: () => _editRule(i),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '编辑规则',
                                      onPressed: () => _editRule(i),
                                      icon: const Icon(Icons.tune),
                                    ),
                                    IconButton(
                                      tooltip: '删除规则',
                                      onPressed: () {
                                        final rules = [..._profile.rules]
                                          ..removeAt(i);
                                        setState(
                                          () => _profile = _profile.copyWith(
                                            rules: rules,
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _profile.rules.length < 100
                                    ? () => _editRule()
                                    : null,
                                icon: const Icon(Icons.add),
                                label: const Text('添加花式得分'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _section(
                        '整局奖励',
                        '全部答对且达到最少题数时，奖励 = 固定奖励 + 题数 × 每题奖励。',
                        _grid([
                          _field('sessionLabel', '整局奖励名称'),
                          _field('sessionMinimum', '最少题数', number: true),
                          _field('sessionBonus', '固定奖励', number: true),
                          _field('sessionPerQuestion', '每题额外奖励', number: true),
                        ]),
                      ),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('保存并应用积分方案'),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );

  String _conditionSummary(ScoringRule rule) {
    final parts = <String>[
      if (rule.minCombo > 0) '连击 ≥ ${rule.minCombo}',
      if (rule.maxElapsedMs > 0) '用时 < ${rule.maxElapsedMs / 1000} 秒',
      if (rule.minRatio > 0)
        '得分 ≥ ${(rule.minRatio * 100).toStringAsFixed(1)}%',
      if (rule.firstAttemptOnly) '首次作答',
      if (rule.previouslyWrongOnly) '错题复习',
      if (rule.materialOnly) '材料题',
      if (rule.excludeMaterial) '排除材料题',
      if (rule.highRoll) '幸运基础分',
      if (rule.challengeOnly) '挑战专属',
      if (rule.group.isNotEmpty) '互斥组 ${rule.group}',
    ];
    return parts.isEmpty ? '答题得分时触发' : parts.join(' · ');
  }
}

class _RuleEditor extends StatefulWidget {
  final ScoringRule rule;
  const _RuleEditor({required this.rule});
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  late Map<String, dynamic> _value;
  String? _error;

  @override
  void initState() {
    super.initState();
    _value = widget.rule.toJson();
    for (final key in [
      'name',
      'group',
      'multiplier',
      'bonus',
      'minCombo',
      'maxElapsedMs',
      'minRatio',
      'highRollThreshold',
    ]) {
      _fields[key] = TextEditingController(text: '${_value[key]}');
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _fields[key],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: key == 'name' || key == 'group'
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      validator: (raw) {
        final text = raw?.trim() ?? '';
        if (key == 'group') return null;
        if (text.isEmpty) return '请填写$label';
        if (key != 'name' &&
            (double.tryParse(text) == null || !double.parse(text).isFinite)) {
          return '请输入有效数字';
        }
        return null;
      },
    ),
  );

  Widget _flag(String key, String label) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: _value[key] as bool,
    onChanged: (v) => setState(() => _value[key] = v ?? false),
  );

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    try {
      final json = {..._value};
      for (final key in ['name', 'group']) {
        json[key] = _fields[key]!.text.trim();
      }
      for (final key in ['multiplier', 'minRatio', 'highRollThreshold']) {
        json[key] = double.parse(_fields[key]!.text.trim());
      }
      for (final key in ['bonus', 'minCombo', 'maxElapsedMs']) {
        json[key] = int.parse(_fields[key]!.text.trim());
      }
      final rule = ScoringRule.fromJson(json);
      rule.validate();
      Navigator.pop(context, rule);
    } catch (e) {
      setState(() => _error = e is FormatException ? e.message : '请检查规则参数');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑花式得分'),
    content: SizedBox(
      width: 600,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field('name', '花式得分名称'),
              _field('multiplier', '倍率（0～1000）'),
              _field('bonus', '额外固定积分（整数）'),
              _field('minCombo', '最少连击数（0 表示不限）'),
              _field('maxElapsedMs', '用时小于（毫秒，0 表示不限）'),
              _field('minRatio', '最低得分比例（0～1）'),
              _field('group', '互斥组（留空可叠加）'),
              DropdownButtonFormField<String>(
                initialValue: _value['questionType'] as String? ?? '',
                decoration: const InputDecoration(
                  labelText: '适用题型',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部题型')),
                  for (final type in QuestionType.values)
                    DropdownMenuItem(
                      value: type.dbValue,
                      child: Text(type.displayName),
                    ),
                ],
                onChanged: (value) =>
                    _value['questionType'] = value == '' ? null : value,
              ),
              const SizedBox(height: 10),
              _flag('enabled', '启用规则'),
              _flag('firstAttemptOnly', '仅首次作答'),
              _flag('previouslyWrongOnly', '仅曾经答错的题目'),
              _flag('challengeOnly', '仅挑战模式'),
              _flag('materialOnly', '仅材料题'),
              _flag('excludeMaterial', '排除材料题'),
              _flag('highRoll', '要求基础分进入幸运区间'),
              if (_value['highRoll'] as bool)
                _field('highRollThreshold', '幸运阈值（0～1，0.8 表示区间最高 20%）'),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('确定')),
    ],
  );
}
