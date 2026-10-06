/// L3 展示级测试 · 仓库路径规则 / 加速通道规则。
///
/// 覆盖用户明确要求的行为：
/// 1. 新建文件的路径**禁止中文与特殊字符**；
/// 2. **禁止空文件**（`.gitkeep` 目录占位例外）；
/// 3. 目录用 `.gitkeep` 占位；
/// 4. 加速通道地址必须是 `https://`（明文 http 会被 Android 9+ 拦截）；
/// 5. 加速地址拼接是纯函数、不会二次加前缀。
library;
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';
import 'package:ohgithublost/surface/util/accel.dart';
import 'package:ohgithublost/surface/util/download_proxy.dart';
import 'package:ohgithublost/surface/util/path_rules.dart';

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

    test('内置通道前缀：proxy.344977.xyz（单前缀，纯转发）', () {
      expect(kOgLAccelBuiltinBaseUrls.length, 1);
      expect(kOgLAccelBuiltinBaseUrls.first, 'https://proxy.344977.xyz/');
      for (final String base in kOgLAccelBuiltinBaseUrls) {
        expect(base.startsWith('https://'), isTrue);
        expect(ogLValidateAccelBaseUrl(base), isNull);
      }
      // 主前缀 = 链首。
      expect(kOgLAccelBuiltinBaseUrl, kOgLAccelBuiltinBaseUrls.first);
      // 对用户仍是**一个**通道（不可删 / 不可改）。
      expect(kOgLAccelBuiltinChannel.builtin, isTrue);
      expect(kOgLAccelBuiltinChannel.baseUrl, kOgLAccelBuiltinBaseUrl);
      // 协议版本已升到 2（换地址属实质修改，必须重新征求同意）。
      expect(kOgLAccelConsentVersion, greaterThanOrEqualTo(2));
    });

    test('加速前缀链：内置是多前缀，自定义是单前缀', () {
      final List<String> builtin = ogLAccelPrefixChain(kOgLAccelBuiltinChannel);
      expect(builtin.length, kOgLAccelBuiltinBaseUrls.length);
      for (final String prefix in builtin) {
        expect(prefix.endsWith('/'), isTrue);
      }
      final List<String> custom = ogLAccelPrefixChain(
        const OgLAccelChannel(id: 'x', name: 'x', baseUrl: 'https://x.com'),
      );
      expect(custom, <String>['https://x.com/']);
    });

    test('候选地址：未启用加速 → 直连', () {
      const String target =
          'https://github.com/o/r/releases/download/v1/a.zip';
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>[],
          family: OgLAccelFamily.signed,
          bytes: 900 * 1024,
        ),
        <String>[target],
      );
    });

    test('候选地址：raw 族只在「内置 + 公开」时加速', () {
      const String target = 'https://raw.githubusercontent.com/o/r/main/a.png';
      const List<String> prefixes = <String>['https://proxy.344977.xyz/'];
      // 内置 + 公开 → 加速（raw 不限流，比 API 配额划算）。
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: prefixes,
          family: OgLAccelFamily.raw,
          bytes: 9 * 1024 * 1024,
          builtinChannel: true,
          repoPrivate: false,
        ),
        <String>['https://proxy.344977.xyz/$target', target],
      );
      // 自定义通道 → 不加速（按既定路由：非内置一律走 API）。
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: prefixes,
          family: OgLAccelFamily.raw,
          bytes: 9 * 1024 * 1024,
          builtinChannel: false,
          repoPrivate: false,
        ),
        <String>[target],
      );
      // 私有仓库 → **永远不加速**：raw 没有签名机制，交给代理等于送令牌。
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: prefixes,
          family: OgLAccelFamily.raw,
          bytes: 9 * 1024 * 1024,
          builtinChannel: true,
          repoPrivate: true,
        ),
        <String>[target],
      );
      // 已知小于阈值 → 不加速（小文件多一跳没收益）。
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: prefixes,
          family: OgLAccelFamily.raw,
          bytes: kOgLAccelMinBytes,
          builtinChannel: true,
          repoPrivate: false,
        ),
        <String>[target],
      );
    });

    test('候选地址：签名族 + 超过阈值 → 前缀 + 直连兜底', () {
      const String target =
          'https://release-assets.githubusercontent.com/x?sig=ab';
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>['https://proxy.344977.xyz/'],
          family: OgLAccelFamily.signed,
          bytes: kOgLAccelMinBytes + 1,
        ),
        <String>['https://proxy.344977.xyz/$target', target],
      );
    });

    test('候选地址：≤ 500KB 不加速（小文件加速没收益）', () {
      const String target = 'https://release-assets.githubusercontent.com/x';
      expect(kOgLAccelMinBytes, 500 * 1024);
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>['https://proxy.344977.xyz/'],
          family: OgLAccelFamily.signed,
          bytes: kOgLAccelMinBytes,
        ),
        <String>[target],
      );
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>['https://proxy.344977.xyz/'],
          family: OgLAccelFamily.signed,
          bytes: 1,
        ),
        <String>[target],
      );
    });

    test('候选地址：大小未知（Action 日志/产物）按加速处理', () {
      const String target = 'https://results-receiver.actions.githubusercontent.com/x';
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>['https://proxy.344977.xyz/'],
          family: OgLAccelFamily.signed,
        ),
        <String>['https://proxy.344977.xyz/$target', target],
      );
    });

    test('候选地址：已是加速地址则不重复加前缀，直连仍垫底', () {
      const String target =
          'https://release-assets.githubusercontent.com/x';
      const String base = 'https://a/';
      expect(
        ogLAccelCandidates(
          url: '$base$target',
          prefixes: const <String>['https://a/', 'https://b/'],
          family: OgLAccelFamily.signed,
          bytes: 9 * 1024 * 1024,
        ),
        <String>['https://b/$base$target', '$base$target'],
      );
    });

    test('候选地址：非 http(s) 原样返回（入队口会拒绝）', () {
      expect(
        ogLAccelCandidates(
          url: 'file:///tmp/a.zip',
          prefixes: const <String>['https://a/'],
          family: OgLAccelFamily.signed,
          bytes: 9 * 1024 * 1024,
        ),
        <String>['file:///tmp/a.zip'],
      );
    });
  });
}