/// 展示层 · 代码高亮词法扫描检查。
///
/// 最关键的纪律：**token 首尾相接必须还原成原文**（否则复制会丢内容）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/widgets/code_view.dart';

/// 把 token 文本拼回去。
String _rejoin(String source, String language) {
  final List<OgLCodeToken> tokens = ogLHighlightCode(source, language);
  return tokens.map((OgLCodeToken t) => t.text).join();
}

void main() {
  group('ogLDetectLanguage', () {
    test('常见扩展名', () {
      expect(ogLDetectLanguage('lib/main.dart'), 'dart');
      expect(ogLDetectLanguage('a.py'), 'python');
      expect(ogLDetectLanguage('a/b/c.ts'), 'typescript');
      expect(ogLDetectLanguage('Dockerfile'), 'shell');
      expect(ogLDetectLanguage('unknown.qqq'), '');
    });
  });

  group('ogLHighlightCode', () {
    test('关键词 / 注释被分类，且可还原原文', () {
      const String src = 'class Foo { // hi\n  int x = 1;\n}';
      final List<OgLCodeToken> tokens = ogLHighlightCode(src, 'dart');
      expect(
        tokens.any((OgLCodeToken t) =>
            t.kind == OgLCodeTokenKind.keyword && t.text == 'class'),
        isTrue,
      );
      expect(
        tokens.any((OgLCodeToken t) => t.kind == OgLCodeTokenKind.comment),
        isTrue,
      );
      expect(_rejoin(src, 'dart'), src);
    });

    test('字符串识别与转义引号', () {
      const String src = r'''var s = "a\"b";''';
      final List<OgLCodeToken> tokens = ogLHighlightCode(src, 'javascript');
      final String joinedStrings = tokens
          .where((OgLCodeToken t) => t.kind == OgLCodeTokenKind.string)
          .map((OgLCodeToken t) => t.text)
          .join();
      expect(joinedStrings.contains(r'a\"b'), isTrue);
      expect(_rejoin(src, 'javascript'), src);
    });

    test('SQL 关键词大小写不敏感', () {
      const String src = 'SELECT * FROM t';
      final List<OgLCodeToken> tokens = ogLHighlightCode(src, 'sql');
      final Iterable<OgLCodeToken> keywords = tokens.where(
        (OgLCodeToken t) => t.kind == OgLCodeTokenKind.keyword,
      );
      expect(keywords.map((OgLCodeToken t) => t.text.toUpperCase()),
          contains('SELECT'));
      expect(_rejoin(src, 'sql'), src);
    });

    test('未闭合字符串 / 块注释不崩溃，且不丢字符', () {
      const String a = 'var s = "unterminated';
      const String b = '/* never ends';
      expect(_rejoin(a, 'dart'), a);
      expect(_rejoin(b, 'dart'), b);
    });

    test('多语言样本可还原原文', () {
      const Map<String, String> samples = <String, String>{
        'dart': 'import "a.dart";\nfinal x = 0x1F; // note\n',
        'python': 'def f(x):\n    return x  # comment\n',
        'go': 'func main() {\n\tfmt.Println("hi")\n}\n',
        'yaml': 'key: value # c\nlist:\n  - 1\n',
        'json': '{"a": true, "b": [1, 2]}\n',
      };
      samples.forEach((String lang, String src) {
        expect(_rejoin(src, lang), src, reason: '语言 $lang 必须无损');
      });
    });
  });

  group('CodeView 极端输入护栏', () {
    testWidgets('超大输入不崩，且能正常渲染', (WidgetTester tester) async {
      final String huge =
          'x' * (kOgLCodeHighlightMaxChars + 1000);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CodeView(code: huge))),
      );
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('海量行不再渲染行号（避免十万组件）',
        (WidgetTester tester) async {
      final String many =
          List<String>.filled(kOgLCodeGutterMaxLines + 5, 'x').join('\n');
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CodeView(code: many))),
      );
      // 行号会被渲染成独立的 '1' / '2' …；超出上限时必须消失。
      expect(find.text('1'), findsNothing);
    });

    testWidgets('常规小文件仍显示行号', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CodeView(code: 'a\nb\nc')),
        ),
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });
}