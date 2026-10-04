/// L3 展示级测试 · 仓库路径规则 / 加速通道规则。
///
/// 覆盖用户明确要求的行为：
/// 1. 新建文件的路径**禁止中文与特殊字符**；
/// 2. **禁止空文件**（`.gitkeep` 目录占位例外）；
/// 3. 目录用 `.gitkeep` 占位；
/// 4. 加速通道地址必须是 `https://`（明文 http 会被 Android 9+ 拦截）；
/// 5. 加速地址拼接是纯函数、不会二次加前缀。
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/util/accel.dart';
import 'package:ohgithublost/surface/util/download_proxy.dart';
import 'package:ohgithublost/surface/util/path_rules.dart';
import 'dart:convert';
import 'dart:io';

import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';

/// 把 zh 分片注入 i18n 内核（测试环境读不到 assets）。
void _loadZh() {
  final Map<String, Map<String, String>> pages =
      <String, Map<String, String>>{};
  for (final String page in <String>['common']) {
    final Object? decoded =
        jsonDecode(File('assets/i18n/zh/$page.json').readAsStringSync());
    pages[page] = <String, String>{
      for (final MapEntry<Object?, Object?> e
          in (decoded as Map<Object?, Object?>).entries)
        '${e.key}': '${e.value}',
    };
  }
  OgLI18n.instance.debugInject('zh', pages);
}

void main() {
  setUpAll(_loadZh);
  group('仓库路径规则', () {
    test('合法路径通过', () {
      expect(ogLValidateRepoEntryPath('src/main.dart', directory: false), isNull);
      expect(ogLValidateRepoEntryPath('docs/api/', directory: true), isNull);
      expect(ogLValidateRepoEntryPath('.gitignore', directory: false), isNull);
      expect(ogLValidateRepoEntryPath('a/b/c_d-e.txt', directory: false), isNull);
    });

    test('禁止中文 / 全角', () {
      expect(
        ogLValidateRepoEntryPath('文档/说明.md', directory: false),
        isNotNull,
      );
      expect(
        ogLValidateRepoEntryPath('src/你好.txt', directory: false),
        isNotNull,
      );
      expect(
        ogLValidateRepoEntryPath('docs（v2）/x.md', directory: false),
        isNotNull,
      );
    });

    test('禁止特殊字符与空格', () {
      for (final String bad in <String>[
        'a b/c.txt',
        'a#b.txt',
        r'a\b.txt',
        'a:b.txt',
        'a*b.txt',
        'a?b.txt',
        'a|b.txt',
        'a<b>.txt',
      ]) {
        expect(
          ogLValidateRepoEntryPath(bad, directory: false),
          isNotNull,
          reason: bad,
        );
      }
    });

    test('结构性错误', () {
      expect(ogLValidateRepoEntryPath('', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('a//b.txt', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('/a.txt', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('a/../b.txt', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('a /b.txt', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('CON', directory: false), isNotNull);
      // 目录必须以 / 结尾；文件不能以 / 结尾。
      expect(ogLValidateRepoEntryPath('docs', directory: true), isNotNull);
      expect(ogLValidateRepoEntryPath('a.txt/', directory: false), isNotNull);
    });

    test('目录占位路径与识别', () {
      expect(ogLGitKeepPathFor('docs/'), 'docs/.gitkeep');
      expect(ogLGitKeepPathFor('docs'), 'docs/.gitkeep');
      expect(ogLGitKeepPathFor(''), '.gitkeep');
      expect(ogLIsGitKeep('docs/.gitkeep'), isTrue);
      expect(ogLIsGitKeep('docs/readme.md'), isFalse);
    });

    test('禁止空文件（.gitkeep 例外）', () {
      expect(ogLValidateFileContent('a.txt', 'hello'), isNull);
      expect(ogLValidateFileContent('a.txt', '   \n  '), isNotNull);
      expect(ogLValidateFileContent('a.txt', ''), isNotNull);
      expect(ogLValidateFileContent('docs/.gitkeep', ''), isNull);
    });
  });

  group('加速通道规则', () {
    test('只接受 https（http 明文会被拦截）', () {
      expect(ogLValidateAccelBaseUrl('https://example.com/'), isNull);
      expect(ogLValidateAccelBaseUrl('http://example.com/'), isNotNull);
      expect(ogLValidateAccelBaseUrl('ftp://example.com/'), isNotNull);
      expect(ogLValidateAccelBaseUrl('https://example.com'), isNotNull);
      expect(ogLValidateAccelBaseUrl('https://例.com/'), isNotNull);
      expect(ogLValidateAccelBaseUrl(''), isNotNull);
    });

    test('内置通道是 https 且被标记为 builtin', () {
      expect(kOgLAccelBuiltinChannel.builtin, isTrue);
      expect(kOgLAccelBuiltinChannel.baseUrl.startsWith('https://'), isTrue);
      expect(ogLValidateAccelBaseUrl(kOgLAccelBuiltinBaseUrl), isNull);
    });

    test('地址归一化补 /', () {
      expect(ogLNormalizeAccelBase('https://a.com'), 'https://a.com/');
      expect(ogLNormalizeAccelBase('https://a.com/'), 'https://a.com/');
    });

    test('拼接不会二次加前缀，也不会改写非 http 地址', () {
      const String base = 'https://a.com/';
      const String target = 'https://github.com/o/r/releases/download/v1/a.zip';
      expect(ogLReleaseDownloadUrl(target, accelBase: base), '$base$target');
      expect(
        ogLReleaseDownloadUrl('$base$target', accelBase: base),
        '$base$target',
      );
      expect(ogLReleaseDownloadUrl(target, accelBase: null), target);
      expect(ogLReleaseDownloadUrl(target, accelBase: ''), target);
      expect(ogLReleaseDownloadUrl('file:///tmp/a.zip', accelBase: base),
          'file:///tmp/a.zip');
    });

    test('协议文本按通道类型区分，且非空', () {
      expect(ogLAccelAgreementFor(kOgLAccelBuiltinChannel), isNotEmpty);
      expect(
        ogLAccelAgreementFor(const OgLAccelChannel(
          id: 'x',
          name: 'x',
          baseUrl: 'https://x/',
        )),
        isNotEmpty,
      );
      expect(
        ogLAccelAgreementFor(kOgLAccelBuiltinChannel),
        isNot(ogLAccelAgreementFor(
          const OgLAccelChannel(id: 'x', name: 'x', baseUrl: 'https://x/'),
        )),
      );
    });
  });
}