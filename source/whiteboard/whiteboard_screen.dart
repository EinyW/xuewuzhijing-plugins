import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointMode;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../models/question.dart';
import '../models/whiteboard.dart';
import '../services/question_service.dart';
import '../services/whiteboard_service.dart';

class WhiteboardScreen extends StatefulWidget {
  final Question? initialQuestion;
  const WhiteboardScreen({super.key, this.initialQuestion});
  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final _board = WhiteboardController();
  final _service = WhiteboardService();
  final _documents = <String>[];
  final _questions = <Question>[];
  final _redoDraft = <Offset>[];
  final _pages = <List<BoardStroke>>[<BoardStroke>[]];
  final _canvasFocus = FocusNode(debugLabel: '白板画布');
  final _transform = TransformationController();
  final _clipboard = <BoardStroke>[];
  final _selectedStrokes = <int>{};
  final _activePointers = <int>{};
  int _pageIndex = 0;
  String _tool = 'pen';
  Rect? _selection;
  Offset? _selectionStart, _moveStart;
  Offset _moveDelta = Offset.zero;
  double _zoom = 1;
  List<FileSystemEntity> _files = [];
  String? _folder, _activePath;
  Question? _question;
  Future<String>? _text;
  Timer? _saveTimer;
  Future<void> _saveQueue = Future.value();
  int? _pointer;
  int _color = 0xff25344a;
  double _width = 3, _split = 0.42;
  bool _eraser = false, _above = true, _grid = true;
  bool _loading = true, _library = true, _referenceVisible = true;
  String _status = '自动保存到本机';

  @override
  void initState() {
    super.initState();
    WhiteboardService.incomingQuestion.addListener(_receiveQuestion);
    _load();
  }

  Future<void> _load() async {
    try {
      final document = await _service.load();
      if (!mounted) return;
      _pages
        ..clear()
        ..addAll(
          document.pages.isEmpty
              ? [document.strokes]
              : document.pages.map(List<BoardStroke>.of),
        );
      _pageIndex = document.activePage.clamp(0, _pages.length - 1);
      _board.restore(_pages[_pageIndex]);
      _documents.addAll(document.documents);
      _questions.addAll(document.questions);
      _split = document.split;
      _above = document.documentAbove;
      _grid = document.grid;
      _question = _questions.firstOrNull;
      if (widget.initialQuestion != null) {
        _addQuestion(widget.initialQuestion!, save: false);
      }
      final incoming = WhiteboardService.incomingQuestion.value;
      if (incoming != null) {
        _addQuestion(incoming, save: false);
        WhiteboardService.incomingQuestion.value = null;
      }
      if (_question == null && _documents.isNotEmpty) {
        _selectPath(_documents.first);
      }
    } catch (_) {
      if (mounted) _status = '原画板读取失败；新内容保存前请先备份原有数据';
    }
    if (mounted) {
      setState(() => _loading = false);
      _board.addListener(_changed);
      if (widget.initialQuestion != null) _changed();
    }
  }

  void _changed() {
    if (!mounted || _loading) return;
    setState(() => _status = '正在保存…');
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), _save);
  }

  void _receiveQuestion() {
    final question = WhiteboardService.incomingQuestion.value;
    if (_loading || question == null || !mounted) return;
    WhiteboardService.incomingQuestion.value = null;
    _addQuestion(question);
  }

  Future<void> _save() {
    _pages[_pageIndex] = List.of(_board.strokes);
    final snapshot = WhiteboardDocument(
      strokes: _board.strokes,
      pages: _pages.map(List<BoardStroke>.of).toList(),
      activePage: _pageIndex,
      documents: List.of(_documents),
      questions: List.of(_questions),
      split: _split,
      documentAbove: _above,
      grid: _grid,
    );
    _saveQueue = _saveQueue
        .then((_) => _service.save(snapshot))
        .then((_) {
          if (mounted) setState(() => _status = '已保存到本机');
        })
        .catchError((Object error) {
          if (mounted) setState(() => _status = '保存失败：$error');
        });
    return _saveQueue;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    WhiteboardService.incomingQuestion.removeListener(_receiveQuestion);
    if (!_loading) _save();
    _board.removeListener(_changed);
    _board.dispose();
    _canvasFocus.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _changePage(int page) {
    if (page < 0 || page >= _pages.length || page == _pageIndex) return;
    _pages[_pageIndex] = List.of(_board.strokes);
    setState(() {
      _pageIndex = page;
      _selectedStrokes.clear();
      _selection = null;
    });
    _board.restore(_pages[page]);
    _changed();
  }

  void _addPage() {
    _pages[_pageIndex] = List.of(_board.strokes);
    setState(() {
      _pages.add(<BoardStroke>[]);
      _pageIndex = _pages.length - 1;
      _selectedStrokes.clear();
      _selection = null;
    });
    _board.restore(const []);
    _changed();
  }

  void _setZoom(double value) {
    setState(() {
      _zoom = value.clamp(.5, 4);
      _transform.value = Matrix4.diagonal3Values(_zoom, _zoom, 1);
    });
  }

  void _copySelection() {
    _clipboard
      ..clear()
      ..addAll(
        _selectedStrokes
            .where((i) => i < _board.strokes.length)
            .map((i) => _board.strokes[i]),
      );
    _toast(_clipboard.isEmpty ? '请先框选笔迹' : '已复制 ${_clipboard.length} 笔');
  }

  BoardStroke _translated(BoardStroke stroke, Offset delta) => BoardStroke(
    points: stroke.points
        .map(
          (p) => Offset(
            (p.dx + delta.dx).clamp(0, 1),
            (p.dy + delta.dy).clamp(0, 1),
          ),
        )
        .toList(),
    color: stroke.color,
    width: stroke.width,
    eraser: stroke.eraser,
  );

  void _pasteSelection() {
    if (_clipboard.isEmpty) {
      _toast('画板剪贴板为空');
      return;
    }
    final strokes = List<BoardStroke>.of(_board.strokes);
    final start = strokes.length;
    strokes.addAll(
      _clipboard.map((s) => _translated(s, const Offset(.03, .03))),
    );
    _board.replace(strokes);
    setState(() {
      _selectedStrokes
        ..clear()
        ..addAll(List.generate(_clipboard.length, (i) => start + i));
      _selection = null;
    });
  }

  void _deleteSelection() {
    if (_selectedStrokes.isEmpty) return;
    final strokes = _board.strokes;
    _board.replace([
      for (var i = 0; i < strokes.length; i++)
        if (!_selectedStrokes.contains(i)) strokes[i],
    ]);
    setState(() {
      _selectedStrokes.clear();
      _selection = null;
    });
  }

  void _historyStep({required bool redo}) {
    if (redo) {
      _board.redo();
    } else {
      _board.undo();
    }
    setState(() {
      _selection = null;
      _selectedStrokes.clear();
    });
  }

  KeyEventResult _canvasKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (control && event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyV) {
      _pasteSelection();
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _historyStep(redo: keyboard.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (control && event.logicalKey == LogicalKeyboardKey.keyY) {
      _historyStep(redo: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelection();
      return KeyEventResult.handled;
    }
    if (!control && event.logicalKey == LogicalKeyboardKey.keyM) {
      setState(() => _tool = 'select');
      return KeyEventResult.handled;
    }
    if (!control && event.logicalKey == LogicalKeyboardKey.keyV) {
      setState(() => _tool = 'move');
      return KeyEventResult.handled;
    }
    if (!control && event.logicalKey == LogicalKeyboardKey.keyB) {
      setState(() {
        _tool = 'pen';
        _eraser = false;
      });
      return KeyEventResult.handled;
    }
    if (!control && event.logicalKey == LogicalKeyboardKey.keyE) {
      setState(() {
        _tool = 'pen';
        _eraser = true;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _addQuestion(Question question, {bool save = true}) {
    if (!_questions.any(
      (q) => q.id == question.id && q.stem == question.stem,
    )) {
      _questions.add(question);
    }
    setState(() {
      _question = question;
      _activePath = null;
      _referenceVisible = true;
      _library = false;
    });
    if (save) _changed();
  }

  Future<void> _removeQuestion(Question question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从画板移除题目？'),
        content: const Text('这只移除画板中的题目，题库中的原题会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _questions.remove(question);
      if (_question == question) _question = null;
    });
    _changed();
  }

  Future<void> _pickQuestion() async {
    try {
      final pool = await QuestionService().getVisibleQuestions();
      if (!mounted) return;
      var keyword = '';
      final selected = await showDialog<Question>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) {
            final filtered = pool
                .where(
                  (q) => q.stem.toLowerCase().contains(keyword.toLowerCase()),
                )
                .toList();
            return AlertDialog(
              title: const Text('从题库添加到画板'),
              content: SizedBox(
                width: 640,
                height: 430,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: '搜索题目',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => update(() => keyword = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('暂无符合条件的题目'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => ListTile(
                                leading: const Icon(Icons.quiz_outlined),
                                title: Text(
                                  filtered[i].stem,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(filtered[i].type.displayName),
                                onTap: () => Navigator.pop(ctx, filtered[i]),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        ),
      );
      if (selected != null && mounted) _addQuestion(selected);
    } catch (error) {
      _toast('读取题库失败：$error');
    }
  }

  Future<void> _importFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;
      String? last;
      for (final file in result.files) {
        if (file.path == null) continue;
        final imported = await _service.importFile(file.path!);
        if (!_documents.contains(imported)) _documents.add(imported);
        last = imported;
      }
      if (!mounted) return;
      if (last != null) _selectPath(last);
      _changed();
    } catch (error) {
      _toast('导入资料失败：$error');
    }
  }

  Future<void> _openFolder([String? path]) async {
    try {
      final selected =
          path ??
          await FilePicker.platform.getDirectoryPath(dialogTitle: '浏览资料文件夹');
      if (selected == null) return;
      final entries = await Directory(selected)
          .list(followLinks: false)
          .toList();
      entries.sort((a, b) {
        final dir = (b is Directory ? 1 : 0) - (a is Directory ? 1 : 0);
        return dir == 0
            ? p
                  .basename(a.path)
                  .toLowerCase()
                  .compareTo(p.basename(b.path).toLowerCase())
            : dir;
      });
      if (mounted) {
        setState(() {
          _folder = selected;
          _files = entries;
          _library = true;
          _referenceVisible = true;
        });
      }
    } catch (error) {
      _toast('无法访问文件夹，请使用「导入资料」选择文件：$error');
    }
  }

  Future<void> _useFile(String path) async {
    try {
      final imported = await _service.importFile(path);
      if (!mounted) return;
      if (!_documents.contains(imported)) _documents.add(imported);
      _selectPath(imported);
      _changed();
    } catch (error) {
      _toast('无法打开资料：$error');
    }
  }

  void _selectPath(String path) {
    final extension = p.extension(path).toLowerCase();
    setState(() {
      _activePath = path;
      _question = null;
      _referenceVisible = true;
      _library = false;
      _text = extension == '.docx'
          ? File(path).readAsBytes().then(WhiteboardService.docxText)
          : ['.txt', '.md', '.csv', '.json', '.log'].contains(extension)
          ? _readText(path)
          : null;
    });
  }

  Future<String> _readText(String path) async {
    if (await File(path).length() > 5 * 1024 * 1024) {
      throw const FormatException('文本过大，请用外部应用打开');
    }
    return File(path).readAsString();
  }

  Future<void> _external(String path) async {
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) _toast('外部打开失败：${result.message}');
    } catch (error) {
      _toast('外部打开失败：$error');
    }
  }

  void _dock(bool above) {
    setState(() {
      _above = above;
      _referenceVisible = true;
    });
    _changed();
  }

  Future<void> _contextMenu(Offset position) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'above', child: Text('资料放在画板上方')),
        PopupMenuItem(value: 'below', child: Text('资料放在画板下方')),
        PopupMenuItem(value: 'hide', child: Text('仅显示画板')),
      ],
    );
    if (!mounted) return;
    if (selected == 'hide') setState(() => _referenceVisible = false);
    if (selected == 'above' || selected == 'below') _dock(selected == 'above');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('讲解画板'),
      actions: [
        IconButton(
          tooltip: '从题库添加',
          onPressed: _pickQuestion,
          icon: const Icon(Icons.add_to_photos_outlined),
        ),
        IconButton(
          tooltip: '导入资料',
          onPressed: _importFiles,
          icon: const Icon(Icons.file_open_outlined),
        ),
        IconButton(
          tooltip: '保存画板',
          onPressed: _loading ? null : _save,
          icon: const Icon(Icons.save_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: '画板布局',
          onSelected: (value) {
            if (value == 'above' || value == 'below') _dock(value == 'above');
            if (value == 'hide') {
              setState(() => _referenceVisible = !_referenceVisible);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'above', child: Text('资料在上，画板在下')),
            PopupMenuItem(value: 'below', child: Text('画板在上，资料在下')),
            PopupMenuItem(value: 'hide', child: Text('显示 / 隐藏资料区')),
          ],
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : DragTarget<Question>(
            onAcceptWithDetails: (details) => _addQuestion(details.data),
            builder: (_, candidates, __) => DecoratedBox(
              decoration: BoxDecoration(
                border: candidates.isNotEmpty
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      )
                    : null,
              ),
              child: Column(
                children: [
                  _tools(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, box) {
                        if (!_referenceVisible) return _canvas();
                        if (box.maxHeight < 240) {
                          return Column(
                            children: [
                              SizedBox(
                                height: 36,
                                child: Row(
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _library = true),
                                      child: const Text('查看资料'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _library = false),
                                      child: const Text('手写画板'),
                                    ),
                                    const Text(
                                      '紧凑布局',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _library ? _references() : _canvas(),
                              ),
                            ],
                          );
                        }
                        final available = (box.maxHeight - 18).clamp(
                          0.0,
                          double.infinity,
                        );
                        final first = available * _split;
                        return Column(
                          children: [
                            SizedBox(
                              height: first,
                              child: _above ? _references() : _canvas(),
                            ),
                            _divider(available),
                            Expanded(child: _above ? _canvas() : _references()),
                          ],
                        );
                      },
                    ),
                  ),
                  Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    child: Text(
                      _status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
  );

  Widget _tools() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        IconButton(
          tooltip: '画笔',
          isSelected: _tool == 'pen' && !_eraser,
          onPressed: () => setState(() {
            _tool = 'pen';
            _eraser = false;
          }),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: '橡皮',
          isSelected: _tool == 'pen' && _eraser,
          onPressed: () => setState(() {
            _tool = 'pen';
            _eraser = true;
          }),
          icon: const Icon(Icons.auto_fix_normal),
        ),
        IconButton(
          tooltip: '框选（M）',
          isSelected: _tool == 'select',
          onPressed: () => setState(() => _tool = 'select'),
          icon: const Icon(Icons.select_all),
        ),
        IconButton(
          tooltip: '移动框选（V）',
          isSelected: _tool == 'move',
          onPressed: () => setState(() => _tool = 'move'),
          icon: const Icon(Icons.open_with),
        ),
        IconButton(
          tooltip: '平移画布',
          isSelected: _tool == 'pan',
          onPressed: () => setState(() => _tool = 'pan'),
          icon: const Icon(Icons.pan_tool_outlined),
        ),
        IconButton(
          tooltip: '复制框选（Ctrl+C）',
          onPressed: _copySelection,
          icon: const Icon(Icons.copy),
        ),
        IconButton(
          tooltip: '粘贴（Ctrl+V）',
          onPressed: _pasteSelection,
          icon: const Icon(Icons.content_paste),
        ),
        IconButton(
          tooltip: '清除框选（Delete）',
          onPressed: _selectedStrokes.isEmpty ? null : _deleteSelection,
          icon: const Icon(Icons.delete_outline),
        ),
        IconButton(
          tooltip: '缩小画布',
          onPressed: () => _setZoom(_zoom / 1.25),
          icon: const Icon(Icons.zoom_out),
        ),
        Text('${(_zoom * 100).round()}%'),
        IconButton(
          tooltip: '放大画布',
          onPressed: () => _setZoom(_zoom * 1.25),
          icon: const Icon(Icons.zoom_in),
        ),
        IconButton(
          tooltip: '上一张画布',
          onPressed: _pageIndex > 0 ? () => _changePage(_pageIndex - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('${_pageIndex + 1}/${_pages.length}'),
        IconButton(
          tooltip: '下一张画布',
          onPressed: _pageIndex + 1 < _pages.length
              ? () => _changePage(_pageIndex + 1)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: '新增画布',
          onPressed: _addPage,
          icon: const Icon(Icons.note_add_outlined),
        ),
        for (final color in [
          0xff25344a,
          0xffdd4444,
          0xff3478db,
          0xff2c986a,
          0xffdf9e28,
        ])
          IconButton(
            tooltip: '选择画笔颜色',
            onPressed: () => setState(() {
              _color = color;
              _eraser = false;
            }),
            icon: Icon(
              _color == color ? Icons.check_circle : Icons.circle,
              color: Color(color),
              size: 22,
            ),
          ),
        SizedBox(
          width: 120,
          child: Slider(
            value: _width,
            min: 1,
            max: 18,
            divisions: 17,
            label: '${_width.round()}',
            onChanged: (v) => setState(() => _width = v),
          ),
        ),
        IconButton(
          tooltip: '撤销',
          onPressed: _board.canUndo ? () => _historyStep(redo: false) : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: '重做',
          onPressed: _board.canRedo ? () => _historyStep(redo: true) : null,
          icon: const Icon(Icons.redo),
        ),
        IconButton(
          tooltip: '网格',
          isSelected: _grid,
          icon: const Icon(Icons.grid_4x4),
          onPressed: () {
            setState(() => _grid = !_grid);
            _changed();
          },
        ),
        IconButton(
          tooltip: '清空笔迹（可撤销）',
          onPressed: _board.strokes.isEmpty ? null : _board.clear,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _openFolder(),
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('文件夹'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _referenceVisible = true;
            _library = !_library;
          }),
          icon: const Icon(Icons.library_books_outlined, size: 18),
          label: const Text('资料与题目'),
        ),
      ],
    ),
  );

  Widget _divider(double available) => MouseRegion(
    cursor: SystemMouseCursors.resizeUpDown,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        if (available <= 0) return;
        setState(
          () =>
              _split = (_split + details.delta.dy / available).clamp(0.2, 0.8),
        );
      },
      onVerticalDragEnd: (_) => _changed(),
      child: Container(
        height: 18,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.drag_handle, size: 18)),
      ),
    ),
  );

  Widget _references() => DragTarget<String>(
    onAcceptWithDetails: (d) {
      _useFile(d.data);
    },
    builder: (_, candidates, __) => GestureDetector(
      onSecondaryTapDown: (d) => _contextMenu(d.globalPosition),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                IconButton(
                  tooltip: '资料列表',
                  onPressed: () => setState(() => _library = !_library),
                  icon: const Icon(Icons.view_sidebar_outlined, size: 18),
                ),
                Expanded(
                  child: Text(
                    _question != null
                        ? '题目与解析'
                        : _activePath != null
                        ? p.basename(_activePath!)
                        : '资料与题目',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_activePath != null)
                  IconButton(
                    tooltip: '使用外部应用打开',
                    onPressed: () => _external(_activePath!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                  ),
                PopupMenuButton<bool>(
                  tooltip: '停靠位置',
                  icon: const Icon(Icons.vertical_align_center, size: 18),
                  onSelected: _dock,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: true, child: Text('停靠在画板上方')),
                    PopupMenuItem(value: false, child: Text('停靠在画板下方')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) {
                final showLibrary =
                    _library || (_activePath == null && _question == null);
                if (showLibrary && box.maxWidth < 740) return _fileList();
                return Row(
                  children: [
                    if (showLibrary) SizedBox(width: 220, child: _fileList()),
                    if (showLibrary) const VerticalDivider(width: 1),
                    Expanded(child: _preview()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fileList() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    children: [
      if (_folder != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.drive_folder_upload_outlined),
          title: Text(
            p.basename(_folder!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: const Text('点击返回上一级'),
          onTap: () => _openFolder(p.dirname(_folder!)),
          trailing: IconButton(
            tooltip: '返回资料库',
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _folder = null),
          ),
        ),
      if (_folder != null)
        for (final entity in _files)
          if (entity is Directory)
            ListTile(
              dense: true,
              leading: const Icon(Icons.folder_outlined),
              title: Text(
                p.basename(entity.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _openFolder(entity.path),
            )
          else if (entity is File)
            _documentTile(entity.path, imported: false),
      if (_folder == null) ...[
        ListTile(
          dense: true,
          leading: const Icon(Icons.add),
          title: const Text('导入图片 / PDF / Word'),
          onTap: _importFiles,
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.add_to_photos_outlined),
          title: const Text('从题库添加题目'),
          onTap: _pickQuestion,
        ),
        for (final question in _questions)
          ListTile(
            dense: true,
            leading: const Icon(Icons.quiz_outlined),
            title: Text(
              question.stem,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _addQuestion(question),
            onLongPress: () => _removeQuestion(question),
            trailing: IconButton(
              tooltip: '从画板移除题目',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => _removeQuestion(question),
            ),
          ),
        for (final path in _documents) _documentTile(path, imported: true),
      ],
    ],
  );

  Widget _documentTile(
    String path, {
    required bool imported,
  }) => Draggable<String>(
    data: path,
    feedback: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(p.basename(path)),
      ),
    ),
    child: ListTile(
      dense: true,
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(
        p.basename(path),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => imported ? _selectPath(path) : _useFile(path),
      onLongPress: () => _useFile(path),
      trailing: PopupMenuButton<String>(
        tooltip: '资料操作',
        onSelected: (value) async {
          if (value == 'above' || value == 'below') {
            await _useFile(path);
            if (mounted) _dock(value == 'above');
          }
          if (value == 'external') _external(path);
          if (value == 'remove') {
            setState(() {
              _documents.remove(path);
              if (_activePath == path) _activePath = null;
            });
            _changed();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'above', child: Text('与画板上下合并 · 资料在上')),
          const PopupMenuItem(value: 'below', child: Text('与画板上下合并 · 资料在下')),
          const PopupMenuItem(value: 'external', child: Text('外部应用打开')),
          if (imported)
            const PopupMenuItem(value: 'remove', child: Text('从资料库移除')),
        ],
      ),
    ),
  );

  Widget _preview() {
    if (_question != null) return _questionPreview(_question!);
    final path = _activePath;
    if (path == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            '导入资料或从题库拖入一道题\n资料区与画板可以上下停靠，拖动中间分隔线调整大小',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!File(path).existsSync()) {
      return Center(child: Text('资料文件已移动或删除：${p.basename(path)}'));
    }
    final extension = p.extension(path).toLowerCase();
    if ([
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.gif',
      '.bmp',
    ].contains(extension)) {
      return InteractiveViewer(
        minScale: 0.2,
        maxScale: 8,
        child: Center(
          child: Image.file(
            File(path),
            errorBuilder: (_, __, ___) => const Text('图片无法读取，请用外部应用打开'),
          ),
        ),
      );
    }
    if (extension == '.pdf') return PdfViewer.file(path, key: ValueKey(path));
    if (_text != null) {
      return Column(
        children: [
          if (extension == '.docx')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Text(
                'Word 兼容模式：预览正文；复杂版式、图片与公式请使用外部应用打开。',
                style: TextStyle(fontSize: 11),
              ),
            ),
          Expanded(
            child: FutureBuilder<String>(
              future: _text,
              builder: (_, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('预览失败：${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SelectableText(
                      snapshot.data!.isEmpty ? '文档中没有可预览的正文' : snapshot.data!,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 32),
            const SizedBox(height: 12),
            Text(
              extension == '.doc'
                  ? '旧版 Word（.doc）使用系统兼容应用查看。\n可另存为 DOCX 或 PDF 后在画板内预览。'
                  : '此格式暂不支持内嵌预览，可使用系统应用查看。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _external(path),
              icon: const Icon(Icons.open_in_new),
              label: const Text('使用外部应用打开'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionPreview(Question question) => SingleChildScrollView(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${question.type.displayName} · ${question.totalScore} 分',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        if (question.material?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          SelectableText(question.material!),
        ],
        const SizedBox(height: 12),
        SelectableText(
          question.stem,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        for (var i = 0; i < (question.options?.length ?? 0); i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              '${String.fromCharCode(65 + i)}. ${question.options![i]}',
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('参考答案与解析'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                [
                  if (question.correctAnswer?.isNotEmpty == true)
                    '参考答案：${question.correctAnswer}',
                  if (question.blanks != null)
                    '参考答案：${question.blanks!.map((b) => b.answer).join('；')}',
                  if (question.explanation?.isNotEmpty == true)
                    question.explanation!,
                  if (question.segments != null)
                    '关键词：${question.segments!.expand((s) => s.keywords).join('、')}',
                ].join('\n\n'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _canvas() => DragTarget<String>(
    onAcceptWithDetails: (details) async {
      await _useFile(details.data);
      if (mounted) _dock(_above);
    },
    builder: (_, candidates, __) => GestureDetector(
      onSecondaryTapDown: (details) => _contextMenu(details.globalPosition),
      child: Focus(
        focusNode: _canvasFocus,
        onKeyEvent: _canvasKey,
        child: LayoutBuilder(
          builder: (_, box) => ClipRect(
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: .5,
              maxScale: 4,
              panEnabled: _tool == 'pan',
              scaleEnabled: true,
              onInteractionUpdate: (_) {
                final scale = _transform.value.getMaxScaleOnAxis().clamp(
                  .5,
                  4.0,
                );
                if ((_zoom - scale).abs() > .01) setState(() => _zoom = scale);
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  _activePointers.add(event.pointer);
                  if (_activePointers.length > 1) {
                    _pointer = null;
                    setState(() {
                      _redoDraft.clear();
                      _selectionStart = null;
                      _moveStart = null;
                    });
                    return;
                  }
                  if (_tool == 'pan' ||
                      _pointer != null ||
                      event.buttons != kPrimaryButton)
                    return;
                  _canvasFocus.requestFocus();
                  _pointer = event.pointer;
                  final point = _normalized(event.localPosition, box.biggest);
                  setState(() {
                    if (_tool == 'select') {
                      _selectionStart = point;
                      _selection = Rect.fromPoints(point, point);
                      _selectedStrokes.clear();
                    } else if (_tool == 'move') {
                      _moveStart = point;
                      _moveDelta = Offset.zero;
                    } else {
                      _redoDraft.clear();
                      _redoDraft.add(point);
                    }
                  });
                },
                onPointerMove: (event) {
                  if (event.pointer != _pointer) return;
                  final point = _normalized(event.localPosition, box.biggest);
                  setState(() {
                    if (_tool == 'select' && _selectionStart != null) {
                      _selection = Rect.fromPoints(_selectionStart!, point);
                    } else if (_tool == 'move' && _moveStart != null) {
                      _moveDelta = _boundedDelta(point - _moveStart!);
                    } else if (_tool == 'pen') {
                      _redoDraft.add(point);
                    }
                  });
                },
                onPointerUp: (event) {
                  _activePointers.remove(event.pointer);
                  if (event.pointer != _pointer) return;
                  _pointer = null;
                  if (_tool == 'select' && _selection != null) {
                    final rectangle = _selection!;
                    final strokes = _board.strokes;
                    setState(() {
                      _selectedStrokes.clear();
                      for (var i = 0; i < strokes.length; i++) {
                        final points = strokes[i].points;
                        if (points.any(rectangle.contains)) {
                          _selectedStrokes.add(i);
                          continue;
                        }
                        for (var j = 1; j < points.length; j++) {
                          if (rectangle.overlaps(
                            Rect.fromPoints(
                              points[j - 1],
                              points[j],
                            ).inflate(.001),
                          )) {
                            _selectedStrokes.add(i);
                            break;
                          }
                        }
                      }
                      _selectionStart = null;
                    });
                  } else if (_tool == 'move' &&
                      _moveStart != null &&
                      _selectedStrokes.isNotEmpty) {
                    final strokes = _board.strokes;
                    final delta = _moveDelta;
                    _board.replace([
                      for (var i = 0; i < strokes.length; i++)
                        _selectedStrokes.contains(i)
                            ? _translated(strokes[i], delta)
                            : strokes[i],
                    ]);
                    setState(() {
                      if (_selection != null)
                        _selection = _selection!.shift(delta);
                      _moveDelta = Offset.zero;
                      _moveStart = null;
                    });
                  } else if (_tool == 'pen') {
                    _board.add(
                      BoardStroke(
                        points: List.of(_redoDraft),
                        color: _color,
                        width: _eraser ? _width * 4 : _width,
                        eraser: _eraser,
                      ),
                    );
                    setState(_redoDraft.clear);
                  }
                },
                onPointerCancel: (event) {
                  _activePointers.remove(event.pointer);
                  _pointer = null;
                  setState(() {
                    _redoDraft.clear();
                    _selectionStart = null;
                    _moveStart = null;
                    _moveDelta = Offset.zero;
                  });
                },
                child: CustomPaint(
                  key: const ValueKey('whiteboard-canvas'),
                  size: Size.infinite,
                  painter: _BoardPainter(
                    strokes: _board.strokes,
                    grid: _grid,
                    selection: _selection,
                    selected: _selectedStrokes,
                    moveDelta: _moveDelta,
                    draft: _redoDraft.isEmpty
                        ? null
                        : BoardStroke(
                            points: List.of(_redoDraft),
                            color: _color,
                            width: _eraser ? _width * 4 : _width,
                            eraser: _eraser,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Offset _boundedDelta(Offset delta) {
    final points = _selectedStrokes
        .where((i) => i < _board.strokes.length)
        .expand((i) => _board.strokes[i].points)
        .toList();
    if (points.isEmpty) return Offset.zero;
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final point in points) {
      minX = point.dx < minX ? point.dx : minX;
      maxX = point.dx > maxX ? point.dx : maxX;
      minY = point.dy < minY ? point.dy : minY;
      maxY = point.dy > maxY ? point.dy : maxY;
    }
    return Offset(
      delta.dx.clamp(-minX, 1 - maxX),
      delta.dy.clamp(-minY, 1 - maxY),
    );
  }

  Offset _normalized(Offset point, Size size) => Offset(
    (point.dx / size.width).clamp(0, 1),
    (point.dy / size.height).clamp(0, 1),
  );
}

class _BoardPainter extends CustomPainter {
  final List<BoardStroke> strokes;
  final BoardStroke? draft;
  final bool grid;
  final Rect? selection;
  final Set<int> selected;
  final Offset moveDelta;
  _BoardPainter({
    required this.strokes,
    required this.grid,
    this.draft,
    this.selection,
    this.selected = const {},
    this.moveDelta = Offset.zero,
  });
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfffdfdfb),
    );
    if (grid) {
      final gridPaint = Paint()
        ..color = const Color(0xffe7e9ec)
        ..strokeWidth = 0.6;
      for (double x = 0; x < size.width; x += 26) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y < size.height; y += 26) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }
    canvas.saveLayer(Offset.zero & size, Paint());
    final visibleStrokes = [...strokes, if (draft != null) draft!];
    for (var index = 0; index < visibleStrokes.length; index++) {
      final stroke = visibleStrokes[index];
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = stroke.eraser ? BlendMode.clear : BlendMode.srcOver;
      Offset scaled(Offset point) {
        final delta = selected.contains(index) ? moveDelta : Offset.zero;
        return Offset(
          (point.dx + delta.dx) * size.width,
          (point.dy + delta.dy) * size.height,
        );
      }

      if (stroke.points.length == 1) {
        canvas.drawPoints(PointMode.points, [
          scaled(stroke.points.first),
        ], paint);
      } else {
        final first = scaled(stroke.points.first);
        final path = Path()..moveTo(first.dx, first.dy);
        for (final point in stroke.points.skip(1)) {
          final current = scaled(point);
          path.lineTo(current.dx, current.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
    if (selection != null) {
      final rect = selection!.shift(moveDelta);
      final painted = Rect.fromLTRB(
        rect.left * size.width,
        rect.top * size.height,
        rect.right * size.width,
        rect.bottom * size.height,
      );
      canvas.drawRect(painted, Paint()..color = const Color(0x224a68d4));
      canvas.drawRect(
        painted,
        Paint()
          ..color = const Color(0xff4a68d4)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}
