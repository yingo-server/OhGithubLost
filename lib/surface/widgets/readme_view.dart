/// L3 展示级 · README / Markdown 渲染（离线安全 + 排版直接取自主题）。
///
/// ## 为什么先做一次"净化"
/// 直接把 GitHub 的 Markdown 丢给渲染器在真机上会踩三个坑：
/// 1. README 常塞几十张**徽章与截图**（`img.shields.io` 等）——本客户端
///    不主动联网取第三方图片，既不安全也拖慢首屏；
/// 2. 大量 HTML 包裹（`<div align="center">`、`<p>`…）在移动端没有意义；
/// 3. 巨型 README（几万字符）一次构建上万个 Widget，滚动直接掉帧。
///
/// 因此 [simplifyReadme] 是一次**纯函数净化**（可单测），
/// 渲染直接把 Markdown 交给 `flutter_markdown`，样式取自当前主题。
library;

import 'package:flutter/material.dart';

import 'package:flutter_markdown/flutter_markdown.dart';

import '../i18n/og_l_i18n.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('common', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 徽章行：`[![alt](图片)](链接)`（可重复；装饰用，整行删除）。
final RegExp _badgeRow = RegExp(r'^(\s*\[!\[[^\)]*\)\]\([^)]*\)\s*)+$');

/// 图片语法：`![alt](url "title")`。
final RegExp _image = RegExp(r'!\[([^\]]*)\]\(([^)\s]*)(?:\s+"[^"]*")?\)');

/// HTML 标签。
final RegExp _htmlTag = RegExp(r'</?[a-zA-Z][^>]*>');

/// HTML 注释。
final RegExp _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// 把原文净化成"离线安全 + 手机友好"的 Markdown。
///
/// 规则（顺序很重要）：
/// 1. 去掉 HTML 注释；
/// 2. 徽章行整行删除；
/// 3. `![alt](url)` → `（图：alt）`（保留信息，不联网取图）；
/// 4. 去掉其余 HTML 标签，只留文本；
/// 5. 连续空行压成一行；
/// 6. 超长按**行边界**截断，并补一行说明（不做静默丢内容）。
String simplifyReadme(String source, {int maxChars = 24000}) {
  final List<String> kept = <String>[];
  bool inFence = false;

  for (final String raw in source.split('\n')) {
    final String line = raw.trimRight();
    final String probe = line.trim();

    // 代码块内部原样保留（代码里的 `<div>`、`![]`、注释都不该被改）。
    if (probe.startsWith('```') || probe.startsWith('~~~')) {
      inFence = !inFence;
      kept.add(line);
      continue;
    }
    if (inFence) {
      kept.add(line);
      continue;
    }

    final String noComment = line.replaceAll(_htmlComment, '').trimRight();
    final String bare = noComment.trim();
    if (bare.isEmpty) {
      kept.add('');
      continue;
    }
    if (_badgeRow.hasMatch(bare)) {
      continue;
    }

    final String swapped = noComment.replaceAllMapped(_image, (Match m) {
      final String alt = m.group(1)?.trim() ?? '';
      return alt.isEmpty ? _t('readmeImageOmitted') : _t('readmeImageAlt', {'alt': alt});
    });
    kept.add(swapped.replaceAll(_htmlTag, '').trimRight());
  }

  // 压缩连续空行。
  final List<String> out = <String>[];
  int blanks = 0;
  for (final String line in kept) {
    if (line.trim().isEmpty) {
      blanks++;
      if (blanks > 1) {
        continue;
      }
    } else {
      blanks = 0;
    }
    out.add(line);
  }
  String md = out.join('\n').trim();

  if (md.length <= maxChars) {
    return md;
  }
  int cut = md.lastIndexOf('\n', maxChars);
  if (cut <= 0) {
    cut = maxChars;
  }
  md = md.substring(0, cut).trimRight();
  return '$md\n\n---\n\n_README 过长，已截断（原文更完整）。_';
}

/// Markdown 视图：净化 + 主题排版 + 链接回调（由调用方决定怎么打开）。
class ReadmeView extends StatelessWidget {
  /// 创建视图。
  const ReadmeView({
    required this.markdown,
    this.onOpenLink,
    this.maxChars = 24000,
    super.key,
  });

  /// 原文（Markdown）。
  final String markdown;

  /// 链接点击（收到完整 URL）。
  final void Function(Uri url)? onOpenLink;

  /// 截断阈值（字符数）。
  final int maxChars;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String md = simplifyReadme(markdown, maxChars: maxChars);
    final TextStyle body = theme.textTheme.bodyMedium ?? const TextStyle();
    final TextStyle mono = const TextStyle(fontFamily: 'monospace');

    return MarkdownBody(
      data: md,
      selectable: true,
      shrinkWrap: true,
      onTapLink: (String text, String? href, String title) {
        final void Function(Uri url)? open = onOpenLink;
        if (href == null || open == null) {
          return;
        }
        final Uri? uri = Uri.tryParse(href);
        if (uri != null) {
          open(uri);
        }
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body.copyWith(height: 1.5),
        h1: theme.textTheme.headlineSmall,
        h2: theme.textTheme.titleLarge,
        h3: theme.textTheme.titleMedium,
        code: mono.copyWith(
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: scheme.outlineVariant, width: 3),
          ),
        ),
        a: TextStyle(color: scheme.primary),
        listBullet: body,
        blockSpacing: 12,
      ),
    );
  }
}