/// 页面纪律护栏：把 `docs/UI_PAGES_PLAN.md` 的"不许"变成**会失败的测试**。
///
/// ## 为什么要有它
/// 用户的验收原话是"现在的 UI 绝对不是严格遵守设计规范写的"。
/// 规范只写在文档里就会退化；写成测试后，退化只可能来自**故意**改测试，
/// 不可能来自"某个页面顺手写了一行 `Colors.red`"。
///
/// ## 规则（对 `lib/surface/pages/*_page.dart` + `lib/surface/app/*.dart`）
/// 1. **每个页面都必须在施工图里有条目**（新页面必须先写规划，不许野生）；
/// 2. 不许出现 Material 视觉：`Colors.` / `Color(0x` / `Icons.` / `SwitchListTile`
///    / `ChoiceChip` / `RadioListTile` / `ListTile(`（颜色只许走调色板与主题常量）；
/// 3. **已重写**的页面必须走统一骨架 `OgLPageScaffold`，且不许自己写
///    `ListView(` / `SingleChildScrollView(`（否则边距与宽屏行为必然发散）；
/// 4. 已重写的页面不许自己判断"`data == null` 就是加载中"（W7 的教训：
///    空结果的 data 同样是 null，于是零项列表永远停在骨架）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 单页规格。
class _Spec {
  const _Spec(this.why, {this.converted = false, this.materialAllow = false});

  /// 在施工图里的定位（人类可读，便于报错时定位）。
  final String why;

  /// 是否已完成"页面级商业重写"（必须走骨架 + 唯一映射点）。
  final bool converted;

  /// 是否暂时允许 Material 行控件（必须在施工图里被点名，且只减不增）。
  final bool materialAllow;
}

/// 页面清单：**新页面必须先在施工图里立项**，否则测试红。
const Map<String, _Spec> _pages = <String, _Spec>{
  'commit_page.dart': _Spec('提交详情（diff）'),
  'dashboard_page.dart': _Spec('首页（我的 / 星标）', converted: true),
  'gists_page.dart': _Spec('Gists'),
  'issue_page.dart': _Spec('议题详情'),
  'login_page.dart': _Spec('登录 / 新增账户向导'),
  'new_issue_page.dart': _Spec('表单页'),
  'new_release_page.dart': _Spec('表单页', materialAllow: true),
  'new_repo_page.dart': _Spec('表单页', materialAllow: true),
  'profile_page.dart': _Spec('我的（账户管理）'),
  'pull_page.dart': _Spec('PR 详情'),
  'repo_page.dart': _Spec('仓库页（骨架 + 元信息盒 + 七标签）', converted: true),
  'search_page.dart': _Spec('搜索（仓库 / 代码）'),
};

/// 应用层文件：这些是"页面之外的壳"，暂未重写，但**不许再用 Material 颜色/图标**。
const Map<String, String> _appFiles = <String, String>{
  'client_shell.dart': '主壳（W8-P3 已重写为自绘导航：底栏 / 导航轨 / 抽屉）',
  'og_l_app.dart': '应用外壳 / 关于页 / 设置页',
  'shell.dart': '布局演示壳（截图测试用）',
};

/// 壳文件里额外禁止的 Material 控件（导航必须与页面同源）。
const Map<String, List<String>> _appForbidden = <String, List<String>>{
  'client_shell.dart': <String>[
    'AppBar(',
    'NavigationBar(',
    'NavigationRail(',
    'NavigationDestination(',
    'ListTile(',
  ],
};

/// 去掉整行注释与块注释，避免"文档里提到 Colors.xxx"被当成违规。
String _code(String source) {
  final String noBlock = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .where((String line) {
        final String t = line.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');
}

List<File> _files(String dir, {required bool Function(String name) pick}) {
  final List<File> list = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((File file) => pick(file.uri.pathSegments.last))
      .toList();
  list.sort((File a, File b) => a.path.compareTo(b.path));
  return list;
}

void main() {
  final String plan =
      File('docs/UI_PAGES_PLAN.md').readAsStringSync();

  test('页面必须先在施工图里立项（不许野生页面）', () {
    final List<File> pages = _files(
      'lib/surface/pages',
      pick: (String name) => name.endsWith('_page.dart'),
    );
    expect(pages, isNotEmpty, reason: '页面目录读不到？');
    for (final File file in pages) {
      final String name = file.uri.pathSegments.last;
      expect(_pages.containsKey(name), isTrue,
          reason: '$name 不在测试清单里：新页面必须先在 UI_PAGES_PLAN 立项，'
              '并在此登记（含是否已重写）。');
      expect(plan.contains(name), isTrue,
          reason: '$name 没写进 docs/UI_PAGES_PLAN.md —— 先规划后写。');
    }
    // 反向：清单里写了的页面必须真的存在（防止删页后清单腐化）。
    for (final String name in _pages.keys) {
      expect(File('lib/surface/pages/$name').existsSync(), isTrue,
          reason: '施工图/清单里的 $name 不存在了，请同步更新。');
    }
  });

  test('页面禁止 Material 视觉（颜色 / 图标字形 / 行控件）', () {
    final List<File> pages = _files(
      'lib/surface/pages',
      pick: (String name) => name.endsWith('_page.dart'),
    );
    for (final File file in pages) {
      final String name = file.uri.pathSegments.last;
      final _Spec? spec = _pages[name];
      final String code = _code(file.readAsStringSync());
      for (final String bad in <String>['Colors.', 'Color(0x', 'Icons.']) {
        expect(code.contains(bad), isFalse,
            reason: '$name（${spec?.why ?? ''}）用了 $bad：'
                '颜色/图标只许走 ogL.palette 与 OgLIcon。');
      }
      if (spec?.materialAllow ?? false) {
        continue;
      }
      for (final String bad in <String>[
        'SwitchListTile',
        'ChoiceChip',
        'RadioListTile',
        'CheckboxListTile',
        'ListTile(',
      ]) {
        expect(code.contains(bad), isFalse,
            reason: '$name 用了 $bad：必须改用 OgLActionRow（+ OgLToggleSwitch）。');
      }
    }
  });

  test('已重写页面必须走统一骨架，且不许自己包滚动视图', () {
    for (final MapEntry<String, _Spec> entry in _pages.entries) {
      if (!entry.value.converted) {
        continue;
      }
      final String name = entry.key;
      final String code = _code(
        File('lib/surface/pages/$name').readAsStringSync(),
      );
      expect(code.contains('OgLPageScaffold'), isTrue,
          reason: '$name 标为已重写，但没有用 OgLPageScaffold（页头/边距/宽屏会发散）。');
      for (final String bad in <String>[
        'ListView(',
        'SingleChildScrollView(',
      ]) {
        expect(code.contains(bad), isFalse,
            reason: '$name 自己写了 $bad：页面滚动与边距只能由 OgLPageScaffold 提供。');
      }
    }
  });

  test('已重写页面不许自己判断"data == null 就是加载中"（W7 教训）', () {
    for (final MapEntry<String, _Spec> entry in _pages.entries) {
      if (!entry.value.converted) {
        continue;
      }
      final String code = _code(
        File('lib/surface/pages/${entry.key}').readAsStringSync(),
      );
      expect(code.contains('data == null &&'), isFalse,
          reason: '${entry.key} 又在手写状态判定：四态只许走 ogLAsyncView。');
    }
  });

  test('应用层壳不许再用 Material 颜色 / 图标字形', () {
    for (final MapEntry<String, String> entry in _appFiles.entries) {
      final File file = File('lib/surface/app/${entry.key}');
      expect(file.existsSync(), isTrue, reason: '${entry.key} 不见了，请同步清单');
      final String code = _code(file.readAsStringSync());
      for (final String bad in <String>['Colors.', 'Icons.']) {
        expect(code.contains(bad), isFalse,
            reason: '${entry.key}（${entry.value}）用了 $bad。');
      }
      expect(code.contains('Color(0x'), isFalse,
          reason: '${entry.key} 直接写了色值字面量：只有主题层可以定义颜色。');
      for (final String bad in _appForbidden[entry.key] ?? const <String>[]) {
        expect(code.contains(bad), isFalse,
            reason: '${entry.key} 还在用 Material 导航控件 $bad：'
                '导航必须与页面同源（用 OgLBottomNav / OgLNavRail / OgLNavDrawer）。');
      }
    }
  });
}