/// L3 展示级 · 文件预览页（图片 / SVG / XML / 音频 / 文本）。
///
/// ## 为什么单独开一页，而不是塞进仓库页
/// 仓库页的「点文件 → 内联看文本」对**位图与音频毫无意义**（二进制当文本看是
/// 乱码），而 SVG 与 XML 既可能想看源码、也可能想看渲染结果。把这些差异收进
/// 一个独立页面，「打开方式」的选择就有了明确落点，也不必改动仓库页既有流程。
///
/// ## 一条如实告知的硬约束
/// 文件内容走 GitHub Contents API，而该接口对**超过 1 MB 的文件不返回内容**。
/// 音频几乎必然超限，所以**不做内置播放**是接口决定的，不是偷懒 —— 页面会
/// 明说原因，并指引到「下载后用系统播放器」。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/file_preview.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/code_editor_field.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('common', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 文件预览页。
class FilePreviewPage extends StatefulWidget {
  /// 创建页面。
  const FilePreviewPage({
    required this.surface,
    required this.fullName,
    required this.path,
    this.branch = 'main',
    this.kind = OgLPreviewKind.image,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 文件路径。
  final String path;

  /// 分支。
  final String branch;

  /// 预览方式（由调用方用 `ogLPreviewKindOf` 判定后传入）。
  final OgLPreviewKind kind;

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  bool _loading = true;
  String? _error;
  Uint8List? _bytes;

  /// 内容超过 Contents API 的单文件上限（1 MB）时为 true。
  bool _tooLarge = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final GhContent? content = await widget.surface.domain.api.content(
        widget.fullName,
        widget.path,
        branch: widget.branch,
      );
      if (!mounted) {
        return;
      }
      if (content == null) {
        setState(() {
          _loading = false;
          _error = _t('previewTooLarge');
        });
        return;
      }
      final String encoding = '${content.raw['encoding'] ?? ''}';
      final String encoded = '${content.raw['content'] ?? ''}';
      if (encoded.isEmpty) {
        // Contents API 对 >1 MB 的文件不回内容 —— 如实说明，不假装加载失败。
        setState(() {
          _loading = false;
          _tooLarge = true;
        });
        return;
      }
      final Uint8List bytes = encoding == 'base64'
          ? base64Decode(encoded.replaceAll('\n', ''))
          : Uint8List.fromList(utf8.encode(encoded));
      setState(() {
        _loading = false;
        _bytes = bytes;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  /// 浏览器里的文件页地址（私有仓库需要登录，故只作兜底）。
  String get _htmlUrl =>
      'https://github.com/${widget.fullName}/blob/${widget.branch}/${widget.path}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ghPathName(widget.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: _t('openInBrowser'),
            onPressed: () =>
                unawaited(openLinkOrCopy(context, _htmlUrl, tag: 'Preview')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final String? error = _error;
    if (error != null) {
      return OgLAsyncErrorPane(message: error, onRetry: _load);
    }
    if (_tooLarge) {
      return _notice(theme, Icons.info_outline, _t('previewTooLarge'));
    }
    final Uint8List? bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      return _notice(theme, Icons.info_outline, _t('previewTooLarge'));
    }
    switch (widget.kind) {
      case OgLPreviewKind.image:
        return _image(bytes);
      case OgLPreviewKind.audio:
        // 音频其实走不到这里（上面大概率已 _tooLarge 命中），保留分支以防
        // 小体积音频文件被确实取回时给出明确指引。
        return _notice(theme, Icons.music_note_outlined, _t('previewAudioHint'));
      case OgLPreviewKind.svg:
      case OgLPreviewKind.xml:
      case OgLPreviewKind.text:
      case OgLPreviewKind.unknown:
        return _text(bytes);
    }
  }

  /// 图片：可缩放查看（Material 自带 `InteractiveViewer`，不引额外依赖）。
  Widget _image(Uint8List bytes) => InteractiveViewer(
        minScale: 0.5,
        maxScale: 6,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                _notice(Theme.of(context), Icons.broken_image_outlined,
                    _t('previewTooLarge')),
          ),
        ),
      );

  /// 文本族（SVG / XML / 其它）：复用既有代码查看器（自带语法高亮与查找）。
  Widget _text(Uint8List bytes) {
    final String source = utf8.decode(bytes, allowMalformed: true);
    return Column(
      children: <Widget>[
        if (widget.kind == OgLPreviewKind.svg)
          _banner(Theme.of(context), Icons.info_outline, _t('previewSvgHint')),
        Expanded(
          child: OgLCodeViewer(
            code: source,
            path: widget.path,
            fontSize: widget.surface.settings.settings.codeFontSize,
            wrap: widget.surface.settings.settings.codeWrap,
            highlight: widget.surface.settings.settings.codeHighlight,
            codeTheme: ogLCodeThemeFor(
              preset: widget.surface.settings.settings.codeThemePreset,
              scheme: Theme.of(context).colorScheme,
              customBackground:
                  widget.surface.settings.settings.codeColorBackground,
              customForeground:
                  widget.surface.settings.settings.codeColorForeground,
              customKeyword: widget.surface.settings.settings.codeColorKeyword,
              customTypeName:
                  widget.surface.settings.settings.codeColorTypeName,
              customString: widget.surface.settings.settings.codeColorString,
              customComment:
                  widget.surface.settings.settings.codeColorComment,
              customNumber: widget.surface.settings.settings.codeColorNumber,
            ),
          ),
        ),
      ],
    );
  }

  Widget _notice(ThemeData theme, IconData icon, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );

  Widget _banner(ThemeData theme, IconData icon, String message) => Container(
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
}