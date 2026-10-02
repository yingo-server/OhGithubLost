/// OGL 展示级 · **把 GitHub 的响应字段翻成人话**（唯一实现处）。
///
/// ## 为什么集中在一处
/// 议题 / PR / 提交 / Gists / 搜索都能拿到"人、时间、文件状态"这三类字段，
/// 早先每个页面各写一份 `_loginOf` / `_dateOf` / `_statusText`：
/// 于是同一个 `added` 有的页面显示 `added`、有的显示"新增"，
/// 日期有的带 `T`、有的不带 —— 用户看到的是"这个 App 各处都不太一样"。
///
/// 这里只保留一组纯函数（无 Flutter 依赖，容易单测）：
/// - [ogLNodeLogin]：从 `user: {login}` 里取登录名；
/// - [ogLDateOnly]：把 ISO 8601 截到"日期"；
/// - [ogLFileStatusText]：`added/modified/removed/renamed/copied` → 中文；
/// - [ogLShortSha]：短 sha（7 位）。
library;

import '../../domain/gh/gh_models.dart';

/// 取节点里的 `user.login`（`user` 不是对象时返回空串）。
String ogLNodeLogin(Map<String, dynamic> node) {
  final Object? user = node['user'];
  if (user is Map<Object?, Object?>) {
    return GhJson.str(Map<String, dynamic>.from(user), 'login');
  }
  return '';
}

/// `created_at` / `updated_at` → `YYYY-MM-DD`（空 / 非法返回空串）。
String ogLDateOnly(Map<String, dynamic> node, String key) {
  final String raw = GhJson.str(node, key);
  if (raw.isEmpty) {
    return '';
  }
  return raw.split('T').first;
}

/// 文件变更状态 → 中文（未知状态原样返回，空则给"变更"）。
String ogLFileStatusText(String status) {
  switch (status) {
    case 'added':
      return '新增';
    case 'removed':
      return '删除';
    case 'modified':
      return '修改';
    case 'renamed':
      return '重命名';
    case 'copied':
      return '复制';
    case 'changed':
      return '变更';
    default:
      return status.isEmpty ? '变更' : status;
  }
}

/// 短 sha（GitHub 网页端也是 7 位）。
String ogLShortSha(String sha) => sha.length >= 7 ? sha.substring(0, 7) : sha;

/// 提交作者显示名（优先 GitHub 登录名，退回本地提交名，再退回"未知"）。
String ogLCommitAuthor(GhCommit commit) =>
    commit.authorLogin ?? commit.authorName ?? '未知';