/// L2 中枢级 · API 逻辑：GitHub 端点封装（并实现底座要求的 [CacheRemote]）。
///
/// 覆盖面：认证 / 仓库 / 分支 / 内容 / 树 / 批量提交 / Releases / 搜索 /
/// 提交历史 / Pages / 组织 / 星标 / Issues / PR / Gist / Actions / 标签。
///
/// **最关键的一段是文件末尾的 [CacheRemote] 实现**：
/// 它把底座的 D1–D7 一致性引擎接到真实 GitHub API 上——
/// `read` 取 sha+内容，`write` 带 sha 提交，409/422 翻译成 [RemoteConflictException]。
/// 没有它，底座再严密也只是空转。
library;

import 'dart:convert';

import '../../base/disk/disk_cache.dart';
import '../../base/disk/disk_types.dart';
import '../../base/net/net_types.dart';
import 'gh_client.dart';
import 'gh_models.dart';

/// GitHub 端点封装。
class GhApi implements CacheRemote {
  /// 创建封装。
  GhApi({required this.client});

  /// 请求客户端。
  final GhClient client;

  static const int _contentSizeLimit = 1024 * 1024; // Contents API 的 1 MB 红线

  // ───────────────────────── 认证 ─────────────────────────

  /// 当前用户。
  Future<GhUser> currentUser() async {
    final object = await client.getObject('/user', label: 'GET /user');
    return GhUser.fromJson(object ?? const <String, dynamic>{});
  }

  /// 额度。
  Future<GhRateLimit?> rateLimit() async {
    final object =
        await client.getObject('/rate_limit', label: 'GET /rate_limit');
    final core = object?['resources'];
    if (core is Map && core['core'] is Map) {
      final coreMap = Map<String, dynamic>.from(core['core'] as Map);
      return GhRateLimit(
        limit: GhJson.integer(coreMap, 'limit'),
        remaining: GhJson.integer(coreMap, 'remaining'),
        resetAt: DateTime.fromMillisecondsSinceEpoch(
          GhJson.integer(coreMap, 'reset') * 1000,
          isUtc: true,
        ),
      );
    }
    return client.lastRateLimit;
  }

  // ───────────────────────── 仓库 ─────────────────────────

  /// 我的仓库。
  Future<List<GhRepo>> myRepos({
    int perPage = 100,
    int page = 1,
    String sort = 'updated',
  }) async {
    final list = await client.getList(
      '/user/repos',
      query: <String, String>{
        'per_page': '$perPage',
        'page': '$page',
        'sort': sort,
        'affiliation': 'owner,collaborator,organization_member',
      },
      label: 'GET /user/repos',
    );
    return list.map(GhRepo.fromJson).toList();
  }

  /// 星标仓库。
  Future<List<GhRepo>> starredRepos({
    int perPage = 100,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/user/starred',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET /user/starred',
    );
    return list.map(GhRepo.fromJson).toList();
  }

  /// 某人名下的公开仓库。
  Future<List<GhRepo>> userRepos(
    String login, {
    int perPage = 100,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/users/$login/repos',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET /users/$login/repos',
    );
    return list.map(GhRepo.fromJson).toList();
  }

  /// 组织仓库。
  Future<List<GhRepo>> orgRepos(
    String org, {
    int perPage = 100,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/orgs/$org/repos',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET /orgs/$org/repos',
    );
    return list.map(GhRepo.fromJson).toList();
  }

  /// 仓库详情。
  Future<GhRepo> repo(String fullName) async {
    final object =
        await client.getObject('/repos/$fullName', label: 'GET /repos/$fullName');
    return GhRepo.fromJson(object ?? const <String, dynamic>{});
  }

  /// 新建仓库。
  Future<GhRepo> createRepo({
    required String name,
    String? description,
    bool private = false,
    bool autoInit = true,
  }) async {
    final response = await client.send(GhRequest(
      path: '/user/repos',
      method: NetMethod.post,
      body: <String, Object?>{
        'name': name,
        if (description != null) 'description': description,
        'private': private,
        'auto_init': autoInit,
      },
      label: 'POST /user/repos',
    ));
    return GhRepo.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  /// 更新仓库设置。
  Future<GhRepo> updateRepo(
    String fullName, {
    String? name,
    String? description,
    bool? private,
    String? defaultBranch,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName',
      method: NetMethod.patch,
      body: <String, Object?>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (private != null) 'private': private,
        if (defaultBranch != null) 'default_branch': defaultBranch,
      },
      label: 'PATCH /repos/$fullName',
    ));
    return GhRepo.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  /// 删除仓库（**危险操作**，调用方必须先二次确认）。
  Future<void> deleteRepo(String fullName) => client
      .send(GhRequest(
        path: '/repos/$fullName',
        method: NetMethod.delete,
        label: 'DELETE /repos/$fullName',
      ))
      .then((_) {});

  /// 复刻。
  Future<GhRepo> fork(String fullName) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/forks',
      method: NetMethod.post,
      label: 'POST /repos/$fullName/forks',
    ));
    return GhRepo.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  /// 加星 / 取消星标。
  Future<void> setStarred(String fullName, bool starred) => client
      .send(GhRequest(
        path: '/user/starred/$fullName',
        method: starred ? NetMethod.put : NetMethod.delete,
        label: '${starred ? 'PUT' : 'DELETE'} /user/starred/$fullName',
      ))
      .then((_) {});

  // ───────────────────────── 分支 ─────────────────────────

  /// 分支列表。
  Future<List<GhBranch>> branches(
    String fullName, {
    int perPage = 100,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/repos/$fullName/branches',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET /repos/$fullName/branches',
    );
    return list.map(GhBranch.fromJson).toList();
  }

  /// 创建分支（基于 [fromSha] 或 [fromBranch]）。
  Future<void> createBranch(
    String fullName, {
    required String name,
    String? fromSha,
    String? fromBranch,
  }) async {
    var sha = fromSha;
    if (sha == null) {
      final source = fromBranch ?? 'main';
      final branchesList = await branches(fullName);
      sha = branchesList
          .firstWhere(
            (GhBranch branch) => branch.name == source,
            orElse: () => const GhBranch(name: '', sha: ''),
          )
          .sha;
    }
    if (sha.isEmpty) {
      throw GhAuthException('无法确定分支 $name 的起点');
    }
    await client.send(GhRequest(
      path: '/repos/$fullName/git/refs',
      method: NetMethod.post,
      body: <String, Object?>{
        'ref': 'refs/heads/$name',
        'sha': sha,
      },
      label: 'POST /repos/$fullName/git/refs',
    ));
  }

  /// 重命名分支。
  Future<void> renameBranch(
    String fullName,
    String from,
    String to,
  ) =>
      client
          .send(GhRequest(
            path: '/repos/$fullName/branches/$from/rename',
            method: NetMethod.post,
            body: <String, Object?>{'new_name': to},
            label: 'POST branch rename',
          ))
          .then((_) {});

  /// 删除分支。
  Future<void> deleteBranch(String fullName, String name) => client
      .send(GhRequest(
        path: '/repos/$fullName/git/refs/heads/$name',
        method: NetMethod.delete,
        label: 'DELETE refs/heads/$name',
      ))
      .then((_) {});

  // ───────────────────────── 内容与树 ─────────────────────────

  /// 目录树（`recursive=1`）。
  ///
  /// 返回的 [GhTree.truncated] 为真时表示**结果不完整**，调用方必须处理。
  Future<GhTree> tree(
    String fullName, {
    String? branch,
    bool recursive = true,
  }) async {
    final ref = branch ?? await _defaultBranchOf(fullName);
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/git/trees/$ref',
      query: recursive ? <String, String>{'recursive': '1'} : const <String, String>{},
      label: 'GET tree($ref)',
    ));
    return GhTree.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  /// 读取内容（文件或目录）。
  Future<GhContent?> content(
    String fullName,
    String path, {
    String? branch,
  }) async {
    try {
      final object = await client.getObject(
        '/repos/$fullName/contents/$path',
        query: <String, String>{if (branch != null) 'ref': branch},
        label: 'GET contents/$path',
      );
      if (object == null) {
        return null;
      }
      // 目录返回数组，这里只取条目信息。
      if (object.containsKey('__list')) {
        return null;
      }
      return GhContent.fromJson(object);
    } on GhNotFoundException {
      return null;
    } on GhAuthException catch (error) {
      // Contents API 对目录可能返回 403（无权限）之外的形态，这里保守返回 null。
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// 列出目录条目。
  Future<List<GhContent>> listDirectory(
    String fullName,
    String path, {
    String? branch,
  }) async {
    try {
      final response = await client.send(GhRequest(
        path: '/repos/$fullName/contents/$path',
        query: <String, String>{if (branch != null) 'ref': branch},
        label: 'GET contents/$path',
      ));
      return response.jsonAsList.map(GhContent.fromJson).toList();
    } on GhNotFoundException {
      return const <GhContent>[];
    }
  }

  /// 读取大文件（>1 MB 时 Contents API 会省略内容，必须走 Blobs）。
  Future<String?> blobText(
    String fullName,
    String sha, {
    String encoding = 'base64',
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/git/blobs/$sha',
      label: 'GET blobs/$sha',
    ));
    final object = response.jsonObject;
    if (object == null) {
      return null;
    }
    final content = GhJson.str(object, 'content');
    return GhContent.decodeContent(content, GhJson.str(object, 'encoding', fallback: encoding));
  }

  /// 写入内容（**带基线 sha → 乐观锁**）。
  Future<GhContent> putContent(
    String fullName,
    String path, {
    required String content,
    required String message,
    String? baseSha,
    String? branch,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/contents/$path',
      method: NetMethod.put,
      body: <String, Object?>{
        'message': message,
        'content': base64Encode(utf8.encode(content)),
        if (baseSha != null) 'sha': baseSha,
        if (branch != null) 'branch': branch,
      },
      label: 'PUT contents/$path',
      // 关键：让 409/422 变成结构化的远端冲突，交给 D2/D3 处理。
      conflictsAsRemoteConflict: true,
    ));
    final object = response.jsonObject ?? const <String, dynamic>{};
    final contentPart = object['content'];
    return GhContent.fromJson(
      contentPart is Map
          ? Map<String, dynamic>.from(contentPart)
          : const <String, dynamic>{},
    );
  }

  /// 删除内容（**危险操作**）。
  Future<void> deleteContent(
    String fullName,
    String path, {
    required String message,
    required String baseSha,
    String? branch,
  }) =>
      client
          .send(GhRequest(
            path: '/repos/$fullName/contents/$path',
            method: NetMethod.delete,
            body: <String, Object?>{
              'message': message,
              'sha': baseSha,
              if (branch != null) 'branch': branch,
            },
            label: 'DELETE contents/$path',
            conflictsAsRemoteConflict: true,
          ))
          .then((_) {});

  /// 批量提交（Git Data API：blob → tree → commit → ref，**原子**）。
  ///
  /// 这是"多文件一次提交"的正路：要么全成、要么全不成，
  /// 不会留下半成品状态。
  Future<String> commitFiles(
    String fullName, {
    required String branch,
    required Map<String, String> upserts,
    List<String> deletions = const <String>[],
    required String message,
    String? expectedHeadSha,
  }) async {
    final entries = <Map<String, Object?>>[];

    for (final MapEntry<String, String> entry in upserts.entries) {
      final blob = await client.send(GhRequest(
        path: '/repos/$fullName/git/blobs',
        method: NetMethod.post,
        body: <String, Object?>{
          'content': base64Encode(utf8.encode(entry.value)),
          'encoding': 'base64',
        },
        label: 'POST blobs(${entry.key})',
      ));
      final blobSha = GhJson.str(
        blob.jsonObject ?? const <String, dynamic>{},
        'sha',
      );
      entries.add(<String, Object?>{
        'path': entry.key,
        'mode': '100644',
        'type': 'blob',
        'sha': blobSha,
      });
    }
    for (final path in deletions) {
      entries.add(<String, Object?>{
        'path': path,
        'mode': '100644',
        'type': 'blob',
        'sha': null,
      });
    }
    if (entries.isEmpty) {
      throw GhAuthException('批量提交内容为空');
    }

    // 以当前分支顶端为基线（若调用方给了期望 sha，则先校验——相当于批量版的 D2）。
    final headSha = await _headShaOf(fullName, branch);
    if (expectedHeadSha != null && headSha != expectedHeadSha) {
      throw RemoteConflictException(
        statusCode: 409,
        currentSha: headSha,
        message: '分支已前进，拒绝批量提交',
      );
    }
    if (headSha.isEmpty) {
      throw GhAuthException('无法确定分支 $branch 的顶端提交');
    }

    final baseTree = await _treeShaOfCommit(fullName, headSha);

    final tree = await client.send(GhRequest(
      path: '/repos/$fullName/git/trees',
      method: NetMethod.post,
      body: <String, Object?>{
        'base_tree': baseTree,
        'tree': entries,
      },
      label: 'POST trees',
    ));
    final treeSha =
        GhJson.str(tree.jsonObject ?? const <String, dynamic>{}, 'sha');

    final commit = await client.send(GhRequest(
      path: '/repos/$fullName/git/commits',
      method: NetMethod.post,
      body: <String, Object?>{
        'message': message,
        'tree': treeSha,
        'parents': <String>[headSha],
      },
      label: 'POST commits',
    ));
    final commitSha =
        GhJson.str(commit.jsonObject ?? const <String, dynamic>{}, 'sha');

    await client.send(GhRequest(
      path: '/repos/$fullName/git/refs/heads/$branch',
      method: NetMethod.patch,
      body: <String, Object?>{
        'sha': commitSha,
        'force': false,
      },
      label: 'PATCH refs/heads/$branch',
      // 引用移动失败同样是冲突。
      conflictsAsRemoteConflict: true,
    ));
    return commitSha;
  }

  // ───────────────────────── 提交历史 ─────────────────────────

  /// 提交历史。
  Future<List<GhCommit>> commits(
    String fullName, {
    String? path,
    String? branch,
    int perPage = 50,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/repos/$fullName/commits',
      query: <String, String>{
        'per_page': '$perPage',
        'page': '$page',
        if (path != null && path.isNotEmpty) 'path': path,
        if (branch != null) 'sha': branch,
      },
      label: 'GET commits',
    );
    return list.map(GhCommit.fromJson).toList();
  }

  /// 两个引用之间的差异（返回 `files` 数组）。
  Future<List<Map<String, dynamic>>> compare(
    String fullName,
    String base,
    String head,
  ) async {
    final object = await client.getObject(
      '/repos/$fullName/compare/$base...$head',
      label: 'GET compare',
    );
    final files = object?['files'];
    if (files is! List) {
      return const <Map<String, dynamic>>[];
    }
    return files
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  // ───────────────────────── Releases ─────────────────────────

  /// 发布列表。
  Future<List<GhRelease>> releases(
    String fullName, {
    int perPage = 30,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/repos/$fullName/releases',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET releases',
    );
    return list.map(GhRelease.fromJson).toList();
  }

  /// 创建发布。
  Future<GhRelease> createRelease(
    String fullName, {
    required String tagName,
    String? name,
    String? body,
    bool prerelease = false,
    String? targetCommitish,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/releases',
      method: NetMethod.post,
      body: <String, Object?>{
        'tag_name': tagName,
        if (name != null) 'name': name,
        if (body != null) 'body': body,
        'prerelease': prerelease,
        if (targetCommitish != null) 'target_commitish': targetCommitish,
      },
      label: 'POST releases',
    ));
    return GhRelease.fromJson(
      response.jsonObject ?? const <String, dynamic>{},
    );
  }

  /// 删除发布。
  Future<void> deleteRelease(String fullName, int releaseId) => client
      .send(GhRequest(
        path: '/repos/$fullName/releases/$releaseId',
        method: NetMethod.delete,
        label: 'DELETE release($releaseId)',
      ))
      .then((_) {});

  // ───────────────────────── 搜索 ─────────────────────────

  /// 搜仓库。
  Future<List<GhRepo>> searchRepos(
    String query, {
    int perPage = 30,
    int page = 1,
  }) async {
    final object = await client.getObject(
      '/search/repositories',
      query: <String, String>{
        'q': query,
        'per_page': '$perPage',
        'page': '$page',
      },
      label: 'GET /search/repositories',
    );
    final items = object?['items'];
    if (items is! List) {
      return const <GhRepo>[];
    }
    return items
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> item) => GhRepo.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  /// 搜代码（**服务端**，消耗 Search 配额）。
  Future<List<Map<String, dynamic>>> searchCode(
    String query, {
    int perPage = 30,
    int page = 1,
  }) async {
    final object = await client.getObject(
      '/search/code',
      query: <String, String>{
        'q': query,
        'per_page': '$perPage',
        'page': '$page',
      },
      label: 'GET /search/code',
    );
    final items = object?['items'];
    if (items is! List) {
      return const <Map<String, dynamic>>[];
    }
    return items
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  // ───────────────────────── Pages ─────────────────────────

  /// 查询 Pages 状态（未启用返回 `null`）。
  Future<Map<String, dynamic>?> pagesInfo(String fullName) async {
    try {
      return await client.getObject(
        '/repos/$fullName/pages',
        label: 'GET pages',
      );
    } on GhNotFoundException {
      return null;
    }
  }

  /// 启用 Pages。
  Future<void> enablePages(
    String fullName, {
    String branch = 'main',
    String path = '/',
  }) =>
      client
          .send(GhRequest(
            path: '/repos/$fullName/pages',
            method: NetMethod.post,
            body: <String, Object?>{
              'source': <String, Object?>{'branch': branch, 'path': path},
            },
            label: 'POST pages',
          ))
          .then((_) {});

  /// 关闭 Pages。
  Future<void> disablePages(String fullName) => client
      .send(GhRequest(
        path: '/repos/$fullName/pages',
        method: NetMethod.delete,
        label: 'DELETE pages',
      ))
      .then((_) {});

  /// 读 CNAME。
  Future<String?> readCname(String fullName) async {
    final content = await this.content(fullName, 'CNAME');
    return content?.text?.trim();
  }

  /// 写 CNAME（自定义域名）。
  Future<void> writeCname(
    String fullName,
    String domain, {
    required String baseSha,
  }) =>
      putContent(
        fullName,
        'CNAME',
        content: '$domain\n',
        message: 'chore: configure custom domain',
        baseSha: baseSha,
      );

  // ───────────────────────── Issues / PR / Gist / Actions ─────────────────────────

  /// Issues 列表（不含 PR）。
  Future<List<Map<String, dynamic>>> issues(
    String fullName, {
    String state = 'open',
    int perPage = 30,
    int page = 1,
  }) =>
      client.getList(
        '/repos/$fullName/issues',
        query: <String, String>{
          'state': state,
          'per_page': '$perPage',
          'page': '$page',
          'filter': 'all',
        },
        label: 'GET issues',
      ).then((List<Map<String, dynamic>> items) => items
          .where((Map<String, dynamic> item) => !item.containsKey('pull_request'))
          .toList());

  /// 新建 Issue。
  Future<Map<String, dynamic>> createIssue(
    String fullName, {
    required String title,
    String? body,
    List<String> labels = const <String>[],
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/issues',
      method: NetMethod.post,
      body: <String, Object?>{
        'title': title,
        if (body != null) 'body': body,
        if (labels.isNotEmpty) 'labels': labels,
      },
      label: 'POST issues',
    ));
    return response.jsonObject ?? const <String, dynamic>{};
  }

  /// 更新 Issue（关闭 / 编辑）。
  Future<Map<String, dynamic>> updateIssue(
    String fullName,
    int number, {
    String? state,
    String? title,
    String? body,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/issues/$number',
      method: NetMethod.patch,
      body: <String, Object?>{
        if (state != null) 'state': state,
        if (title != null) 'title': title,
        if (body != null) 'body': body,
      },
      label: 'PATCH issues/$number',
    ));
    return response.jsonObject ?? const <String, dynamic>{};
  }

  /// Issue 评论。
  Future<List<Map<String, dynamic>>> issueComments(
    String fullName,
    int number,
  ) =>
      client.getList(
        '/repos/$fullName/issues/$number/comments',
        label: 'GET issue comments',
      );

  /// PR 列表。
  Future<List<Map<String, dynamic>>> pulls(
    String fullName, {
    String state = 'open',
    int perPage = 30,
    int page = 1,
  }) =>
      client.getList(
        '/repos/$fullName/pulls',
        query: <String, String>{
          'state': state,
          'per_page': '$perPage',
          'page': '$page',
        },
        label: 'GET pulls',
      );

  /// PR 的文件变更。
  Future<List<Map<String, dynamic>>> pullFiles(
    String fullName,
    int number,
  ) =>
      client.getList(
        '/repos/$fullName/pulls/$number/files',
        label: 'GET pull files',
      );

  /// Gist 列表。
  Future<List<Map<String, dynamic>>> gists({int perPage = 30}) =>
      client.getList(
        '/gists',
        query: <String, String>{'per_page': '$perPage'},
        label: 'GET gists',
      );

  /// Actions 运行列表。
  Future<List<Map<String, dynamic>>> workflowRuns(
    String fullName, {
    int perPage = 20,
  }) async {
    final object = await client.getObject(
      '/repos/$fullName/actions/runs',
      query: <String, String>{'per_page': '$perPage'},
      label: 'GET actions/runs',
    );
    final runs = object?['workflow_runs'];
    if (runs is! List) {
      return const <Map<String, dynamic>>[];
    }
    return runs
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// 标签列表。
  Future<List<Map<String, dynamic>>> labels(String fullName) =>
      client.getList('/repos/$fullName/labels', label: 'GET labels');

  /// README（Markdown 原文）。
  Future<String?> readme(String fullName) async {
    final content = await this.content(fullName, 'README.md');
    if (content?.text != null) {
      return content!.text;
    }
    try {
      final object = await client.getObject(
        '/repos/$fullName/readme',
        label: 'GET readme',
      );
      final encoded = GhJson.str(object ?? const <String, dynamic>{}, 'content');
      return GhContent.decodeContent(
        encoded,
        GhJson.str(object ?? const <String, dynamic>{}, 'encoding', fallback: 'base64'),
      );
    } on GhNotFoundException {
      return null;
    }
  }

  // ───────────────────────── ★ CacheRemote 实现 ─────────────────────────

  /// 读取远端文档（给一致性引擎用）。
  ///
  /// 大文件（>1 MB）会经 Blobs API 补齐内容——**绝不返回"空内容"当成功**。
  @override
  Future<RemoteDocument?> read(CacheKey key) async {
    final repo = key.scope.repo;
    final branch = key.scope.branch;
    final object = await _contentsObject(repo, key.path, branch);
    if (object == null) {
      return null;
    }
    final parsed = GhContent.fromJson(object);
    var text = parsed.text;
    // Contents API 对 >1 MB 的文件会省略 content（且不报错），
    // 这里显式改走 Blobs API —— 否则会"静默拿到空内容"。
    final oversized = parsed.size > _contentSizeLimit;
    if (text == null && (parsed.isTooLarge || oversized)) {
      text = await blobText(repo, parsed.sha);
    }
    if (text == null) {
      // 拿不到内容就当作不存在，**不返回空串**——空串会被写回远端，是数据事故。
      return null;
    }
    return RemoteDocument(content: text, sha: parsed.sha);
  }

  /// 按期望 sha 写入（给一致性引擎用）。
  ///
  /// 409/422 会被翻译成 [RemoteConflictException]，交由 D2/D3 处理。
  @override
  Future<RemoteDocument> write(
    CacheKey key,
    String content, {
    required String message,
    String? expectedSha,
  }) async {
    final repo = key.scope.repo;
    final branch = key.scope.branch;
    final written = await putContent(
      repo,
      key.path,
      content: content,
      message: message,
      baseSha: expectedSha,
      branch: branch,
    );
    return RemoteDocument(content: content, sha: written.sha);
  }

  // ───────────────────────── 内部辅助 ─────────────────────────

  Future<Map<String, dynamic>?> _contentsObject(
    String fullName,
    String path,
    String? branch,
  ) async {
    try {
      return await client.getObject(
        '/repos/$fullName/contents/$path',
        query: <String, String>{if (branch != null) 'ref': branch},
        label: 'GET contents/$path',
      );
    } on GhNotFoundException {
      return null;
    }
  }

  Future<String> _defaultBranchOf(String fullName) async {
    final object = await client.getObject('/repos/$fullName');
    return GhJson.str(object ?? const <String, dynamic>{}, 'default_branch',
        fallback: 'main');
  }

  Future<String> _headShaOf(String fullName, String branch) async {
    try {
      final object = await client.getObject(
        '/repos/$fullName/git/ref/heads/$branch',
      );
      final target = object?['object'];
      if (target is Map) {
        return GhJson.str(Map<String, dynamic>.from(target), 'sha');
      }
    } on GhNotFoundException {
      return '';
    }
    return '';
  }

  Future<String> _treeShaOfCommit(String fullName, String commitSha) async {
    final object = await client.getObject(
      '/repos/$fullName/git/commits/$commitSha',
    );
    final tree = object?['tree'];
    if (tree is Map) {
      return GhJson.str(Map<String, dynamic>.from(tree), 'sha');
    }
    return '';
  }
}