/// README 净化器的层内检查（纯函数，不需要 widget）。
///
/// 这些断言对应真机上的三类事故：
/// 1. 徽章/截图把首屏拖死（本客户端"零外部资源"，不许联网取第三方图）；
/// 2. HTML 包裹让移动端排版出现莫名空行；
/// 3. 巨型 README 一次构建上万个 Widget，滚动掉帧。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/readme/readme_view.dart';

void main() {
  group('ogLSimplifyReadme · 离线安全', () {
    test('图片换成占位文本（不保留任何 URL）', () {
      final String out = ogLSimplifyReadme(
        '看图：![架构图](https://example.com/a.png) 完。',
      );
      expect(out.contains('（图：架构图）'), isTrue);
      expect(out.contains('http'), isFalse, reason: '不许留下图片 URL');
      expect(out.contains('!['), isFalse);
    });

    test('无 alt 的图片也给可读占位', () {
      final String out = ogLSimplifyReadme('![](https://x/y.png)');
      expect(out.contains('（图，已省略）'), isTrue);
    });

    test('徽章行整行删除，正文里的链接保留', () {
      const String src = ''''
[![CI](https://img.shields.io/badge/ci-pass-green)](https://ci.example.com)
[![LICENSE](https://img.shields.io/badge/license-MIT-blue)](https://x/y)

# 标题

文档见 [手册](https://example.com/doc)。
''';
      final String out = ogLSimplifyReadme(src);
      expect(out.contains('img.shields.io'), isFalse, reason: '整行徽章必须消失');
      expect(out.contains('（图：CI）'), isFalse, reason: '徽章行连占位都不该留');
      expect(out.contains('# 标题'), isTrue);
      expect(out.contains('[手册](https://example.com/doc)'), isTrue,
          reason: '正文链接必须原样保留（点了要能开）');
    });

    test('HTML 标签与注释被清掉，文本留下', () {
      const String src = '''
<!-- 这是注释 -->
<div align="center">
  <p>第一段</p>
  <br/>
  <details><summary>展开</summary>内容</details>
</div>
''';
      final String out = ogLSimplifyReadme(src);
      expect(out.contains('<'), isFalse, reason: 'HTML 标签必须清干净');
      expect(out.contains('这是注释'), isFalse);
      expect(out.contains('第一段'), isTrue);
      expect(out.contains('展开'), isTrue);
    });

    test('代码块内部原样保留（标签/图片/注释都不许动）', () {
      const String src = '''
示例：

```html
<!-- 保留我 -->
<div class="x">![](https://y/z.png)</div>
```
''';
      final String out = ogLSimplifyReadme(src);
      expect(out.contains('<!-- 保留我 -->'), isTrue);
      expect(out.contains('<div class="x">'), isTrue);
      expect(out.contains('!['), isTrue, reason: '代码块里的图片语法是示例内容');
    });

    test('连续空行压成一行', () {
      final String out = ogLSimplifyReadme('A\n\n\n\nB');
      expect(out, 'A\n\nB');
    });

    test('超长截断：在行边界截断并明确告知', () {
      final String src = List<String>.generate(200, (int i) => '第 $i 行内容').join('\n');
      final String out = ogLSimplifyReadme(src, maxChars: 200);
      expect(out.length < 400, isTrue);
      expect(out.contains('已截断'), isTrue, reason: '截断必须可见（不许静默丢内容）');
      expect(out.contains('第 0 行内容'), isTrue);
    });

    test('没有 README 内容时返回空串（交给空态处理）', () {
      expect(ogLSimplifyReadme(''), isEmpty);
      expect(ogLSimplifyReadme('\n\n  \n'), isEmpty);
    });
  });
}