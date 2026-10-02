/// OGL 展示级 · README 渲染（Markdown → 令牌化排版 + **离线安全**）。
///
/// ## 这个文件解决什么
/// 仓库页此前**完全没有 README**（`GhApi.readme()` 早就写好，但从没接到界面上）。
/// 直接把 Markdown 丢给渲染器在真机上会踩三个坑：
/// 1. GitHub 的 README 里常塞几十张**徽章与截图**（`img.shields.io` 等），
///    本客户端有"零外部资源"红线 —— 联网取第三方图片既慢又可能拉死首屏；
/// 2. 大量 HTML 包裹（`<div align="center">`、`<p>`、`<details>`）在移动端没有意义，
///    却会让排版出现莫名空行；
/// 3. 巨型 README（几万字符）一次构建上万个 Widget，滚动直接掉帧。
///
/// 因此这里先做**一次纯函数净化**（[ogLSimplifyReadme]，可单测），
/// 再用 `flutter_markdown` 渲染，样式全部来自令牌与调色板。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// 徽章行：GitHub 上给网页看的装饰，形态是 `[![alt](图片)](链接)`（可重复）。
///
/// 注意区分：**单独一张图**（`![](logo.png)`）要保留（换成占位文本），
/// 只有"图片包在链接里"的徽章行才整行删除 —— 否则用户会以为 README 是空的。
final RegExp _badgeRow = RegExp(r'^(\s*\[!\[[^\)]*\)\]\([^)]*\)\s*)+$');

/// 图片语法：`![alt](url "title")`。
final RegExp _image = RegExp(r'!\[([^\]]*)\]\(([^)\s]*)(?:\s+"[^"]*")?\)');

/// HTML 标签（README 里常见：div / p / br / img / details / summary / kbd…）。
final RegExp _htmlTag = RegExp(r'</?[a-zA-Z][^>]*>');

/// HTML 注释。
final RegExp _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// 把 README 原文净化成"离线安全 + 手机友好"的 Markdown。
///
/// 规则（顺序很重要）：
/// 1. 去掉 HTML 注释；
/// 2. 徽章行整行删除（连续多行也随之消失，不留空行）；
/// 3. `![alt](url)` → `图：alt`（保留信息，不联网取图）；
/// 4. 去掉其余 HTML 标签，只留文本；
/// 5. 连续空行压成一行；
/// 6. 超长则按**行边界**截断，并补一行说明（不做静默丢内容）。
String ogLSimplifyReadme(String source, {int maxChars = 24000}) {
  final List<String> kept = <String>[];
  bool inFence = false;

  for (final String raw in source.split('\n')) {
    final String line = raw.trimRight();
    final String probe = line.trim();

    // 代码块内部**原样保留**（代码里出现 `<div>`、`![]`、`<!-- -->` 都不该被改）。
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
    // 装饰性徽章行：`[![alt](图)](链接)` —— 整行去掉，不留占位（那是给网页看的）。
    if (_badgeRow.hasMatch(bare)) {
      continue;
    }

    final String swapped = noComment.replaceAll(_image, (Match m) {
      final String alt = m.group(1)?.trim() ?? '';
      return alt.isEmpty ? '（图，已省略）' : '（图：$alt）';
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

/// README 视图：净化 + 令牌化排版 + 链接回调（由页面决定怎么打开）。
class OgLReadmeView extends StatelessWidget {
  /// 创建 README 视图。
  const OgLReadmeView({
    required this.markdown,
    this.onOpenLink,
    this.maxChars = 24000,
    super.key,
  });

  /// README 原文（Markdown）。
  final String markdown;

  /// 链接点击（收到完整 URL）。
  final void Function(Uri url)? onOpenLink;

  /// 截断阈值（字符数）。
  final int maxChars;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final String md = ogLSimplifyReadme(markdown, maxChars: maxChars);
    final TextStyle p = TextStyle(
      fontSize: tokens.fontSize(scale.body),
      height: 1.55,
      color: ogL.palette.text,
    );

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
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: p,
        h1: p.copyWith(
          fontSize: tokens.fontSize(scale.headline),
          fontWeight: FontWeight.w600,
        ),
        h2: p.copyWith(
          fontSize: tokens.fontSize(scale.title),
          fontWeight: FontWeight.w600,
        ),
        h3: p.copyWith(
          fontSize: tokens.fontSize(scale.body),
          fontWeight: FontWeight.w600,
        ),
        code: TextStyle(
          fontFamily: kOgLMonoFamily,
          fontSize: tokens.fontSize(scale.data),
          color: ogL.palette.text,
          backgroundColor: ogL.palette.surfaceAlt,
        ),
        codeblockDecoration: BoxDecoration(
          color: ogL.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(tokens.radius(OgLRadius.small)),
          border: Border.all(
            color: ogL.palette.border,
            width: tokens.hairline,
          ),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: ogL.palette.border,
              width: tokens.stroke(OgLStroke.thick),
            ),
          ),
        ),
        a: TextStyle(color: ogL.palette.accent),
        listBullet: p.copyWith(color: ogL.palette.textDim),
        listIndent: tokens.space(OgLSpacing.lg),
        blockSpacing: tokens.space(OgLSpacing.md),
      ),
    );
  }
}