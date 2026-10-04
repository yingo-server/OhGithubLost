/// L3 展示级 · 轻量国际化（i18n）。
///
/// ## 设计要点
/// 1. **JSON 分片、按页面组织**：`assets/i18n/<locale>/<page>.json`
///    （page = `common` / `shell` / `settings` / `repo` / `login`…）。
///    要改某个页面的文案，只动那一个文件即可，不用翻一个巨型翻译表。
/// 2. **英文基线 + 就近兜底**：缺失键依次回落「当前语言 → 英文 → 键名」，
///    绝不因为漏翻而显示空白。
/// 3. **中文语境保留英文术语**：`issue` / `release` / `action` / `pr` 等
///    在 `zh` 分片里**原样保留英文**（按产品要求）。
/// 4. 不引入 `intl`：本需求只需"查表替换"，无需复数/日期本地化
///    （日期由 GitHub 原样返回，系统组件文案由 `flutter_localizations` 负责）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

/// 一个可选语言。
@immutable
class OgLLocale {
  /// 创建语言项。
  const OgLLocale(this.code, this.label);

  /// 语言代码（同时是目录名）。
  final String code;

  /// 原生展示名（下拉框里显示）。
  final String label;
}

/// i18n 内核（全局单例；仅展示层使用）。
class OgLI18n extends ChangeNotifier {
  OgLI18n._();

  /// 全局实例。
  static final OgLI18n instance = OgLI18n._();

  /// 基线语言（任何缺失键的最终兜底）。
  static const String baseLocale = 'en';

  /// 全部可选语言（约 15 种常用语言）。
  static const List<OgLLocale> locales = <OgLLocale>[
    OgLLocale('zh', '简体中文'),
    OgLLocale('zh_TW', '繁體中文'),
    OgLLocale('en', 'English'),
    OgLLocale('ja', '日本語'),
    OgLLocale('ko', '한국어'),
    OgLLocale('fr', 'Français'),
    OgLLocale('de', 'Deutsch'),
    OgLLocale('es', 'Español'),
    OgLLocale('pt', 'Português'),
    OgLLocale('ru', 'Русский'),
    OgLLocale('ar', 'العربية'),
    OgLLocale('hi', 'हिन्दी'),
    OgLLocale('th', 'ไทย'),
    OgLLocale('vi', 'Tiếng Việt'),
    OgLLocale('id', 'Bahasa Indonesia'),
  ];

  /// 需要加载的页面分片（新增页面时在这里补一项即可）。
  static const List<String> pages = <String>[
    'about_page',
    'action_log_page',
    'action_run_page',
    'code_editor_page',
    'commit_page',
    'common',
    'dashboard_page',
    'download_manager_page',
    'drafts_page',
    'gist_detail_page',
    'gists_page',
    'issue_page',
    'login',
    'new_gist_page',
    'new_issue_page',
    'new_release_page',
    'new_repo_page',
    'notifications_page',
    'onboarding',
    'profile_page',
    'pull_page',
    'release_detail_page',
    'repo',
    'search_page',
    'settings',
    'shell',
    'workflow_dispatch_page',
  ];

  String _locale = 'zh';
  // locale → page → key → value
  final Map<String, Map<String, Map<String, String>>> _data =
      <String, Map<String, Map<String, String>>>{};

  /// 当前语言代码。
  String get locale => _locale;

  /// 当前语言的展示名。
  String get localeLabel {
    for (final OgLLocale item in locales) {
      if (item.code == _locale) {
        return item.label;
      }
    }
    return _locale;
  }

  /// 加载某语言的全部页面分片（同时确保英文基线已加载）。
  ///
  /// **永不抛**：单个分片读取失败只记录，不阻断应用（缺键会兜底到英文）。
  Future<void> load(String code) async {
    final String target = _isSupported(code) ? code : 'zh';
    // 基线必须先有，否则兜底链断裂。
    if (!_data.containsKey(baseLocale)) {
      await _loadLocale(baseLocale);
    }
    if (!_data.containsKey(target)) {
      await _loadLocale(target);
    }
    if (_locale != target) {
      _locale = target;
      notifyListeners();
    }
  }

  bool _isSupported(String code) {
    for (final OgLLocale item in locales) {
      if (item.code == code) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadLocale(String code) async {
    final Map<String, Map<String, String>> pagesData =
        <String, Map<String, String>>{};
    for (final String page in pages) {
      pagesData[page] = await _loadPage(code, page);
    }
    _data[code] = pagesData;
  }

  Future<Map<String, String>> _loadPage(String code, String page) async {
    try {
      final String raw =
          await rootBundle.loadString('assets/i18n/$code/$page.json');
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <String, String>{};
      }
      return <String, String>{
        for (final MapEntry<Object?, Object?> e in decoded.entries)
          '${e.key}': '${e.value}',
      };
    } catch (_) {
      // 分片缺失 / 解析失败：返回空表，交给兜底链（英文 → 键名）。
      return const <String, String>{};
    }
  }

  /// 取文案：`t('shell', 'home')`；需要插值用 `t('repo', 'deleted', args: {'path': p})`。
  ///
  /// 兜底顺序：当前语言 → 英文基线 → 键名（**绝不返回空串**）。
  ///
  /// 占位符：文案里写 `{path}`，调用时传 `args: {'path': ...}`；
  /// 缺参时**保留原样**（`{path}`）而不是抛异常——UI 不该因为缺一个参数就崩。
  String t(String page, String key, {Map<String, String>? args}) {
    final String raw = _raw(page, key);
    if (args == null || args.isEmpty) {
      return raw;
    }
    String out = raw;
    for (final MapEntry<String, String> entry in args.entries) {
      out = out.replaceAll('{${entry.key}}', entry.value);
    }
    return out;
  }

  /// 原始文案（当前语言 → 英文基线 → 键名）。
  String _raw(String page, String key) {
    final String? current = _data[_locale]?[page]?[key];
    if (current != null && current.isNotEmpty) {
      return current;
    }
    final String? base = _data[baseLocale]?[page]?[key];
    if (base != null && base.isNotEmpty) {
      return base;
    }
    return key;
  }

  /// 仅测试用：注入内存数据（避免测试环境读不到 assets）。
  @visibleForTesting
  void debugInject(
    String code,
    Map<String, Map<String, String>> pagesData,
  ) {
    _data[code] = pagesData;
    _locale = code;
  }
}