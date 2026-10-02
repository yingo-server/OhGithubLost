/// 视图格式化 + 动效令牌的层内检查（纯逻辑，不需要 widget）。
///
/// 对应两件事：
/// 1. **E3 代码之美**：`user.login` / 日期 / 文件状态这些"翻人话"的逻辑
///    只能有一份实现（[ogLNodeLogin] / [ogLDateOnly] / [ogLFileStatusText]），
///    否则同一个 `added` 在不同页面会显示成不同样子；
/// 2. **E1 动效**：``减少动效`` 必须**真的归零**，紧凑密度必须真的更快 ——
///    无障碍开关与密度选择不能只是"看起来生效"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/gh/gh_models.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/util/gh_view_format.dart';

void main() {
  group('gh_view_format · 翻人话只有一处实现', () {
    test('登录名：user 是对象才取 login，否则空串', () {
      expect(
        ogLNodeLogin(<String, dynamic>{
          'user': <String, dynamic>{'login': 'octocat'},
        }),
        'octocat',
      );
      expect(ogLNodeLogin(<String, dynamic>{'user': 'octocat'}), isEmpty);
      expect(ogLNodeLogin(<String, dynamic>{}), isEmpty);
    });

    test('日期：ISO 8601 截到天；空值给空串（不是 null 也不是 1970）', () {
      expect(
        ogLDateOnly(<String, dynamic>{'created_at': '2026-10-02T06:00:00Z'}, 'created_at'),
        '2026-10-02',
      );
      expect(ogLDateOnly(<String, dynamic>{}, 'created_at'), isEmpty);
      expect(ogLDateOnly(<String, dynamic>{'x': 5}, 'x'), isEmpty);
    });

    test('文件状态：GitHub 的英文状态 → 中文；未知原样、空给"变更"', () {
      expect(ogLFileStatusText('added'), '新增');
      expect(ogLFileStatusText('modified'), '修改');
      expect(ogLFileStatusText('removed'), '删除');
      expect(ogLFileStatusText('renamed'), '重命名');
      expect(ogLFileStatusText('copied'), '复制');
      expect(ogLFileStatusText('whatever'), 'whatever');
      expect(ogLFileStatusText(''), '变更');
    });

    test('短 sha：7 位（不足则原样）', () {
      expect(ogLShortSha('0123456789abcdef'), '0123456');
      expect(ogLShortSha('abc'), 'abc');
      expect(ogLShortSha(''), isEmpty);
    });

    test('提交作者：登录名 → 提交名 → 未知', () {
      expect(
        ogLCommitAuthor(
          const GhCommit(
            sha: 'a',
            message: 'm',
            authorLogin: 'octocat',
            authorName: 'Mona',
          ),
        ),
        'octocat',
      );
      expect(
        ogLCommitAuthor(
          const GhCommit(sha: 'a', message: 'm', authorName: 'Mona'),
        ),
        'Mona',
      );
      expect(ogLCommitAuthor(const GhCommit(sha: 'a', message: 'm')), '未知');
    });
  });

  group('design_tokens · 减少动效与密度', () {
    test('减少动效 ⇒ 一切动效时长为 0（无障碍开关必须真的生效）', () {
      final OgLTokens tokens = OgLTokens.resolve(reducedMotion: true);
      expect(tokens.motion(OgLDuration.fast), Duration.zero);
      expect(tokens.motion(OgLDuration.base), Duration.zero);
      expect(tokens.motion(OgLDuration.slow), Duration.zero);
    });

    test('默认：时长原样保留', () {
      final OgLTokens tokens = OgLTokens.resolve();
      expect(tokens.motion(OgLDuration.base), OgLDuration.base);
    });

    test('紧凑密度：比 fast 更长的动效要再快一档', () {
      final OgLTokens tokens =
          OgLTokens.resolve(density: OgLDensity.compact);
      final Duration slow = tokens.motion(OgLDuration.slow);
      expect(slow.inMilliseconds < OgLDuration.slow.inMilliseconds, isTrue);
      // 最短档不动（已经足够快）。
      expect(tokens.motion(OgLDuration.fast), OgLDuration.fast);
    });

    test('字号缩放被夹紧（系统给 3.0 也不能把布局拉爆）', () {
      final OgLTokens tokens = OgLTokens.resolve(textScale: 3);
      expect(tokens.textScale <= 2.0, isTrue);
    });
  });
}