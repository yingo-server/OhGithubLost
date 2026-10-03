/// L3 展示级 · 全屏代码编辑器（**编辑态语法高亮 + 内建撤销/重做**）。
///
/// 相对旧版的两处关键改进：
/// 1. **高亮**：编辑区改为「高亮图层 + 透明输入层」叠加，编辑时即可见语法高亮
///    （`highlight` 系库要求 Dart < 3，故复用项目既有词法器 `CodeView`）；
/// 2. **撤销/重做**：改用 Flutter 内建的 [UndoHistoryController]，
///    语义与输入法一致，不再依赖自研防抖快照栈（旧版"撤销不灵敏"）。
///
/// 其余能力保留：查找/替换、换行/字号、未保存拦截、草稿防抖落盘、
/// 加锁保存（走 D1–D7，基线过期弹冲突对话框）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/gh/gh_client.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import '../widgets/code_view.dart';

/// 全屏代码编辑器页。
class CodeEditorPage extends StatefulWidget {
  /// 创建页面。
  const CodeEditorPage({
    required this.surface,
    required this.fullName,
    required this.path,
    required this.initialText,
    required this.baseSha,
    this.branch,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 文件路径。
  final String path;

  /// 初始内容。
  final String initialText;

  /// 编辑基线（乐观锁）。
  final String baseSha;

  /// 分支。
  final String? branch;

  @override
  State<CodeEditorPage> createState() => _CodeEditorPageState();
}

class _CodeEditorPageState extends State<CodeEditorPage> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();

  /// Flutter 内建撤销/重做历史。
  final UndoHistoryController _undoHistory = UndoHistoryController();

  bool _showFind = false;
  bool _wrap = false;
  double _fontSize = 13;
  bool _saving = false;
  bool _saved = false;

  /// 草稿自动保存（防抖）。
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _text.text = widget.initialText;
    _undoHistory.addListener(_onHistoryChanged);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    unawaited(_persistDraft());
    _undoHistory.removeListener(_onHistoryChanged);
    _undoHistory.dispose();
    _text.dispose();
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 进入编辑器时尝试恢复上次未提交的草稿。
  Future<void> _restoreDraft() async {
    try {
      final String? draft = await widget.surface.domain.api.loadDraft(
        widget.fullName,
        widget.path,
        branch: widget.branch,
      );
      if (!mounted || draft == null) {
        return;
      }
      if (draft == widget.initialText) {
        await widget.surface.domain.api.discardDraft(
          widget.fullName,
          widget.path,
          branch: widget.branch,
        );
        return;
      }
      setState(() {
        _text.text = draft;
      });
      _toast('已恢复上次未提交的草稿');
    } catch (_) {
      // 草稿读取失败不影响编辑。
    }
  }

  /// 把当前文本写入草稿（与远端一致则清掉草稿）。
  Future<void> _persistDraft() async {
    try {
      if (_text.text == widget.initialText) {
        await widget.surface.domain.api.discardDraft(
          widget.fullName,
          widget.path,
          branch: widget.branch,
        );
        return;
      }
      await widget.surface.domain.api.saveDraft(
        widget.fullName,
        widget.path,
        _text.text,
        branch: widget.branch,
        baseSha: widget.baseSha,
      );
    } catch (_) {
      // 草稿落盘失败不阻断编辑。
    }
  }

  bool get _dirty => _text.text != widget.initialText;

  void _onChanged() {
    // 草稿落盘防抖：停顿后再写，避免高频写盘。
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 900), _persistDraft);
    setState(() {});
  }

  void _toggleWrap() => setState(() => _wrap = !_wrap);

  void _changeFont(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(10.0, 24.0).toDouble());
  }

  // ───────────────────────── 查找 / 替换 ─────────────────────────

  void _findNext() {
    final String needle = _find.text;
    if (needle.isEmpty) {
      return;
    }
    final String haystack = _text.text;
    final TextSelection sel = _text.selection;
    int from = sel.isValid ? sel.end : 0;
    if (from < 0 || from > haystack.length) {
      from = 0;
    }
    int index = haystack.indexOf(needle, from);
    if (index < 0) {
      index = haystack.indexOf(needle); // 回绕到开头再试一次。
    }
    if (index < 0) {
      _toast('未找到：$needle');
      return;
    }
    _text.selection = TextSelection(
      baseOffset: index,
      extentOffset: index + needle.length,
    );
  }

  void _replaceCurrent() {
    final String needle = _find.text;
    if (needle.isEmpty) {
      return;
    }
    final TextSelection sel = _text.selection;
    final bool selectedMatches = sel.isValid &&
        sel.start >= 0 &&
        sel.end <= _text.text.length &&
        _text.text.substring(sel.start, sel.end) == needle;
    if (selectedMatches) {
      final String next = _text.text.replaceRange(sel.start, sel.end, _replace.text);
      _text.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: sel.start + _replace.text.length),
      );
      _onChanged();
    } else {
      _findNext();
    }
  }

  void _replaceAll() {
    final String needle = _find.text;
    if (needle.isEmpty) {
      return;
    }
    final int count = needle.allMatches(_text.text).length;
    if (count == 0) {
      _toast('未找到：$needle');
      return;
    }
    _text.text = _text.text.replaceAll(needle, _replace.text);
    _onChanged();
    _toast('已替换 $count 处');
  }

  // ───────────────────────── 保存 ─────────────────────────

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      GhWriteResult result = await widget.surface.domain.api.putContentLocked(
        widget.fullName,
        widget.path,
        content: _text.text,
        message: 'docs: update ${widget.path}',
        baseSha: widget.baseSha,
        branch: widget.branch,
      );
      if (!result.ok && result.canForceOverwrite) {
        final bool? overwrite = await _showConflictDialog(result);
        if (overwrite != true) {
          _toast('已取消：远端已被更新，未覆盖');
          return;
        }
        result = await widget.surface.domain.api.putContentLocked(
          widget.fullName,
          widget.path,
          content: _text.text,
          message: 'docs: update ${widget.path}',
          baseSha: widget.baseSha,
          branch: widget.branch,
          force: true,
          confirmed: true,
        );
      }
      if (!result.ok) {
        OgLAppLog.instance.add(
          '编辑',
          '提交失败（${result.conflict.name}）：${result.detail ?? ''}',
          severity: OgLNoticeSeverity.critical,
        );
        if (mounted) {
          _toast('提交失败：${result.detail ?? result.conflict.name}');
        }
        return;
      }
      OgLAppLog.instance.result('编辑', '已提交', widget.path);
      await widget.surface.domain.api.discardDraft(
        widget.fullName,
        widget.path,
        branch: widget.branch,
      );
      _saved = true;
      if (mounted) {
        _toast('已提交修改：${widget.path}');
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        '编辑',
        '提交失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        _toast('提交失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool?> _showConflictDialog(GhWriteResult result) => showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('远端已更新，可能覆盖他人改动'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('你的基线：${_short(result.baseSha)}'),
                Text('远端最新：${_short(result.sha)}'),
                const SizedBox(height: 8),
                const Text('直接覆盖会丢弃远端这一次改动。'),
                if (result.remoteContent != null) ...<Widget>[
                  const SizedBox(height: 12),
                  const Text('远端最新内容：'),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _preview(result.remoteContent!),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消（保留远端）'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('强制覆盖'),
            ),
          ],
        ),
      );

  Future<bool?> _confirmDiscard() => showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('放弃未保存的修改？'),
          content: const Text('当前修改尚未提交，返回将丢失这些改动。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _short(String? sha) =>
      sha == null || sha.isEmpty ? '—' : (sha.length <= 8 ? sha : sha.substring(0, 8));

  static String _preview(String text) =>
      text.length <= 4000 ? text : '${text.substring(0, 4000)}\n…（已截断预览）';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _EditorPrefs prefs = _EditorPrefs(widget.surface);
    final TextStyle codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: 1.5,
      color: Colors.transparent, // 文字透明：可见颜色来自下层高亮图层
    );
    final int lines = '\n'.allMatches(_text.text).length + 1;
    return PopScope(
      canPop: !_dirty || _saved,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final bool? leave = await _confirmDiscard();
        if (leave == true && context.mounted) {
          Navigator.of(context).pop(_saved);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: '撤销',
              onPressed: _undoHistory.canUndo ? _undoHistory.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: '重做',
              onPressed: _undoHistory.canRedo ? _undoHistory.redo : null,
            ),
            IconButton(
              icon: Icon(_showFind ? Icons.search_off : Icons.search),
              tooltip: '查找 / 替换',
              onPressed: () => setState(() => _showFind = !_showFind),
            ),
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '保存',
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            if (_showFind) _findBar(theme),
            Expanded(child: _editorBody(prefs, codeStyle)),
            _statusBar(theme, lines),
          ],
        ),
      ),
    );
  }

  /// 编辑区：高亮图层（不可交互）+ 透明输入层，两层同字号同边距以对齐。
  Widget _editorBody(_EditorPrefs prefs, TextStyle codeStyle) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: CodeView(
                code: _text.text.isEmpty ? ' ' : _text.text,
                language: ogLDetectLanguage(widget.path),
                fontSize: _fontSize,
                wrap: true,
                highlight: prefs.highlight,
                showLineNumbers: false,
                codeTheme: prefs.theme(context),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _text,
              undoController: _undoHistory,
              onChanged: (_) => _onChanged(),
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: codeStyle,
              cursorColor: Theme.of(context).colorScheme.primary,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _findBar(ThemeData theme) => Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _find,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: '查找',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    tooltip: '查找下一个',
                    onPressed: _findNext,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _replace,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: '替换为',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _replaceCurrent, child: const Text('替换')),
                  TextButton(onPressed: _replaceAll, child: const Text('全部')),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _statusBar(ThemeData theme, int lines) => Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$lines 行 · ${_text.text.length} 字符'
                  '${_dirty ? ' · 未保存' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(_wrap ? Icons.wrap_text : Icons.notes),
                tooltip: _wrap ? '关闭自动换行' : '开启自动换行',
                onPressed: _toggleWrap,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove),
                tooltip: '减小字号',
                onPressed: () => _changeFont(-1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add),
                tooltip: '增大字号',
                onPressed: () => _changeFont(1),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.visibility_outlined),
                tooltip: '预览（只读高亮）',
                onPressed: _previewSheet,
              ),
            ],
          ),
        ),
      );

  void _previewSheet() {
    final _EditorPrefs settings = _EditorPrefs(widget.surface);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.8,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: CodeView(
            code: _text.text,
            language: ogLDetectLanguage(widget.path),
            fontSize: settings.fontSize,
            wrap: _wrap,
            highlight: settings.highlight,
            codeTheme: settings.theme(sheetContext),
          ),
        ),
      ),
    );
  }
}

/// 读取当前设置的小助手（避免在多处重复取 settings）。
class _EditorPrefs {
  /// 创建。
  const _EditorPrefs(this.surface);

  /// 表面桥。
  final SurfaceBridge surface;

  /// 代码字号。
  double get fontSize => surface.settings.settings.codeFontSize;

  /// 是否启用高亮。
  bool get highlight => surface.settings.settings.codeHighlight;

  /// 解析代码配色。
  OgLCodeTheme theme(BuildContext context) => ogLCodeThemeFor(
        preset: surface.settings.settings.codeThemePreset,
        scheme: Theme.of(context).colorScheme,
        customBackground: surface.settings.settings.codeColorBackground,
        customForeground: surface.settings.settings.codeColorForeground,
        customKeyword: surface.settings.settings.codeColorKeyword,
        customTypeName: surface.settings.settings.codeColorTypeName,
        customString: surface.settings.settings.codeColorString,
        customComment: surface.settings.settings.codeColorComment,
        customNumber: surface.settings.settings.codeColorNumber,
      );
}