import 'package:flutter/material.dart';

import '../models/question.dart';
import '../screens/whiteboard_screen.dart';
import '../services/plugin_service.dart';
import 'workspace_navigation.dart';

/// 显式拖动手柄避免触屏滚动题库时意外拖动整行。
class QuestionBoardHandle extends StatelessWidget {
  final Question question;
  const QuestionBoardHandle({super.key, required this.question});

  void _open(BuildContext context) {
    final workspace = WorkspaceNavigation.maybeOf(context);
    if (workspace != null) {
      workspace.openWhiteboard(question);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WhiteboardScreen(initialQuestion: question),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PluginService.instance.whiteboardEnabled) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onSecondaryTapDown: (details) async {
        final chosen = await showMenu<bool>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: const [PopupMenuItem(value: true, child: Text('发送到讲解画板'))],
        );
        if (chosen == true && context.mounted) _open(context);
      },
      child: Draggable<Question>(
        data: question,
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 280,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                question.stem,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        child: IconButton(
          tooltip: '发送画板（拖动、点击或右键）',
          icon: const Icon(Icons.drag_indicator, size: 20),
          onPressed: () => _open(context),
        ),
      ),
    );
  }
}
