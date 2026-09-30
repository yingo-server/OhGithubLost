/// L1 底座级 · 缓存一致性测试（七道防线 D1–D7）。
///
/// 这是全项目**最关键的测试**：它保证用户的代码不会被错位覆盖。
/// 每一条用例都直接对应 `docs/CONSISTENCY.md` 中的一道防线，
/// 并且全部跑在内存远端上——不依赖 GitHub、不依赖网络。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_cache.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/disk/disk_types.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';

/// 内存远端：可注入冲突、并发探针与"回读损坏"。
class FakeCacheRemote implements CacheRemote {
  /// 内容库。
  final Map<String, RemoteDocument> store = <String, RemoteDocument>{};

  /// 写入次数。
  int writeCount = 0;

  /// 实际发生的冲突次数。
  int conflictCount = 0;

  /// 检测到的并发写入（>0 表示串行化失败）。
  int concurrentDetected = 0;

  int _forcedConflicts = 0;
  bool _writing = false;

  /// 写入后把远端内容改成别的版本（用于验证 D5 回读校验）。
  bool corruptReadback = false;

  /// 排期若干次冲突。
  void simulateConflict(int times) => _forcedConflicts = times;

  /// 预置一个远端文档。
  void seed(CacheKey key, String content, String sha) {
    store[key.encode()] = RemoteDocument(content: content, sha: sha);
  }

  @override
  Future<RemoteDocument?> read(CacheKey key) async => store[key.encode()];

  @override
  Future<RemoteDocument> write(
    CacheKey key,
    String content, {
    required String message,
    String? expectedSha,
  }) async {
    if (_writing) {
      concurrentDetected++;
    }
    _writing = true;
    try {
      // 让出事件循环：给"并发写"留出交错的机会。
      await Future<void>.delayed(Duration.zero);
      writeCount++;

      final current = store[key.encode()];
      if (_forcedConflicts > 0) {
        _forcedConflicts--;
        conflictCount++;
        throw RemoteConflictException(statusCode: 409, currentSha: current?.sha);
      }
      if (expectedSha != null &&
          current != null &&
          expectedSha != current.sha) {
        conflictCount++;
        throw RemoteConflictException(statusCode: 409, currentSha: current.sha);
      }

      final document = RemoteDocument(
        content: content,
        sha: 'sha-r$writeCount',
      );
      store[key.encode()] = document;
      if (corruptReadback) {
        store[key.encode()] =
            RemoteDocument(content: 'tampered', sha: 'sha-tampered');
      }
      return document;
    } finally {
      _writing = false;
    }
  }
}

/// 测试用作用域。
const CacheScope _scopeA = CacheScope(
  schemaVersion: 1,
  accountId: 'acct-A',
  repo: 'owner/repo',
  branch: 'main',
);

const CacheKey _keyA = CacheKey(scope: _scopeA, path: 'README.md');

void main() {
  late FakeCacheRemote remote;
  late KernelDiagnostics diagnostics;
  late RepositoryCache cache;

  setUp(() {
    remote = FakeCacheRemote();
    diagnostics = KernelDiagnostics();
    cache = RepositoryCache(
      remote: remote,
      index: InMemoryKv(),
      blobs: InMemoryFileStore(),
      diagnostics: diagnostics,
      maxConflictRetries: 2,
    );
  });

  group('作用域（错位覆盖的第一道闸）', () {
    test('非法作用域被拒绝进入缓存层', () async {
      const broken = CacheKey(
        scope: CacheScope(
          schemaVersion: 1,
          accountId: '',
          repo: 'owner/repo',
          branch: 'main',
        ),
        path: 'a.txt',
      );
      await expectLater(
        cache.read(broken),
        throwsA(isA<CacheScopeException>()),
      );
    });

    test('不同账号 / 分支的内容互相隔离', () async {
      const otherAccount = CacheKey(
        scope: CacheScope(
          schemaVersion: 1,
          accountId: 'acct-B',
          repo: 'owner/repo',
          branch: 'main',
        ),
        path: 'README.md',
      );
      remote.seed(_keyA, 'A-content', 'sha-a');
      remote.seed(otherAccount, 'B-content', 'sha-b');

      final a = await cache.read(_keyA, refresh: true);
      final b = await cache.read(otherAccount, refresh: true);
      expect(a?.content, 'A-content');
      expect(b?.content, 'B-content');
      expect(a?.sha, isNot(b?.sha));
    });

    test('作用域编解码可往返，非法串解析为 null', () {
      expect(CacheScope.parse(_scopeA.encode()), _scopeA);
      expect(CacheScope.parse('1|only|three'), isNull);
      expect(CacheScope.parse('x|a|b|c'), isNull);
      expect(CacheScope.parse('1||b|c'), isNull);
    });
  });

  group('D1 写前必读', () {
    test('缺少基线 SHA 直接拒绝', () async {
      final outcome = await cache.write(
        const WriteIntent(key: _keyA, content: 'x', message: 'test'),
      );
      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.requiresRead);
      expect(remote.writeCount, 0);
    });
  });

  group('D2 SHA 乐观锁', () {
    test('基线过期时拒绝写入并回传远端最新版本', () async {
      remote.seed(_keyA, 'remote-v2', 'sha-v2');
      final outcome = await cache.write(
        const WriteIntent(
          key: _keyA,
          content: 'mine',
          message: 'test',
          baseSha: 'sha-v1',
        ),
      );
      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.staleSha);
      expect(outcome.sha, 'sha-v2');
      expect(remote.writeCount, 0);
    });

    test('基线一致时写入成功', () async {
      remote.seed(_keyA, 'remote-v1', 'sha-v1');
      final outcome = await cache.write(
        const WriteIntent(
          key: _keyA,
          content: 'mine',
          message: 'test',
          baseSha: 'sha-v1',
        ),
      );
      expect(outcome.ok, isTrue);
      expect(outcome.attempts, 1);
      expect(remote.store[_keyA.encode()]?.content, 'mine');
    });
  });

  group('D3 冲突重试', () {
    test('提供重定基函数时自动重试并合并', () async {
      remote.seed(_keyA, 'remote-v1', 'sha-v1');
      remote.simulateConflict(1);

      final outcome = await cache.write(
        WriteIntent(
          key: _keyA,
          content: 'mine',
          message: 'merge',
          baseSha: 'sha-v1',
          rebase: (String latest, String my) => '$latest+$my',
        ),
      );

      expect(outcome.ok, isTrue);
      expect(outcome.attempts, 2);
      expect(remote.conflictCount, 1);
      expect(remote.store[_keyA.encode()]?.content, 'remote-v1+mine');
    });

    test('未提供重定基函数时拒绝自动覆盖（宁失败不越权）', () async {
      remote.seed(_keyA, 'remote-v1', 'sha-v1');
      remote.simulateConflict(1);

      final outcome = await cache.write(
        const WriteIntent(
          key: _keyA,
          content: 'mine',
          message: 'no-rebase',
          baseSha: 'sha-v1',
        ),
      );

      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.staleSha);
      expect(outcome.detail, contains('拒绝自动覆盖'));
    });

    test('超过重试上限后上报（有界重试，不会死循环）', () async {
      remote.seed(_keyA, 'remote-v1', 'sha-v1');
      remote.simulateConflict(9);

      final outcome = await cache.write(
        WriteIntent(
          key: _keyA,
          content: 'mine',
          message: 'boom',
          baseSha: 'sha-v1',
          rebase: (String latest, String my) => '$latest|$my',
        ),
      );

      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.staleSha);
      // 1 次失败 + 不超过上限的重试
      expect(outcome.attempts, lessThanOrEqualTo(3));
    });
  });

  group('D4 本地写队列串行化', () {
    test('并发写同一目标不会交错执行', () async {
      remote.seed(_keyA, 'base', 'sha-0');

      final futures = <Future<WriteOutcome>>[];
      for (var index = 0; index < 5; index++) {
        futures.add(cache.write(
          WriteIntent(
            key: _keyA,
            content: 'v$index',
            message: 'm$index',
            baseSha: 'sha-0',
          ),
        ));
      }
      final outcomes = await Future.wait(futures);

      expect(remote.concurrentDetected, 0, reason: '同键写操作绝不允许交错');
      // 只有第一个持有有效基线：其余因为基线过期被 D2 拦下，而不是被覆盖。
      expect(outcomes.where((outcome) => outcome.ok).length, 1);
      expect(
        outcomes.where((outcome) => outcome.conflict == WriteConflict.staleSha).length,
        4,
      );
    });
  });

  group('D5 写后失效与回读校验', () {
    test('回读指纹不一致时判定失败，并清掉本地缓存', () async {
      remote.seed(_keyA, 'remote-v1', 'sha-v1');
      remote.corruptReadback = true;

      final outcome = await cache.write(
        const WriteIntent(
          key: _keyA,
          content: 'mine',
          message: 'test',
          baseSha: 'sha-v1',
        ),
      );

      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.verificationFailed);
      expect(
        await cache.localCount(),
        0,
        reason: '校验失败后不得留下任何本地条目',
      );
    });

    test('写入成功会刷新本地缓存（写后回读结果一致）', () async {
      remote.seed(_keyA, 'remote-v1', 'sha-v1');
      final outcome = await cache.write(
        const WriteIntent(
          key: _keyA,
          content: 'mine',
          message: 'test',
          baseSha: 'sha-v1',
        ),
      );
      expect(outcome.ok, isTrue);
      expect(await cache.localCount(), 1);
    });
  });

  group('D6 失败可感知', () {
    test('每次失败都带回可读原因且记入诊断', () async {
      final outcome = await cache.write(
        const WriteIntent(key: _keyA, content: 'x', message: 'test'),
      );
      expect(outcome.detail, isNotNull);
      expect(diagnostics.errorCount, greaterThan(0));
      expect(
        diagnostics.logTail.any((entry) => entry.code == 'OGL-CONS-201'),
        isTrue,
      );
    });
  });

  group('D7 危险操作二次确认', () {
    test('未确认时拒绝执行危险写入', () async {
      remote.seed(_keyA, 'remote-v1', 'sha-v1');
      final outcome = await cache.write(
        const WriteIntent(
          key: _keyA,
          content: '',
          message: 'delete',
          baseSha: 'sha-v1',
          dangerous: true,
        ),
      );
      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.needsConfirmation);
      expect(remote.writeCount, 0);
    });

    test('确认后放行', () async {
      remote.seed(_keyA, 'remote-v1', 'sha-v1');
      final outcome = await cache.write(
        const WriteIntent(
          key: _keyA,
          content: 'gone',
          message: 'delete',
          baseSha: 'sha-v1',
          dangerous: true,
        ),
        confirmed: true,
      );
      expect(outcome.ok, isTrue);
    });
  });

  group('读取与失效', () {
    test('二次读取命中本地，不回源', () async {
      remote.seed(_keyA, 'cached', 'sha-c');
      final first = await cache.read(_keyA);
      expect(first?.content, 'cached');

      remote.store.remove(_keyA.encode()); // 远端"消失"
      final second = await cache.read(_keyA);
      expect(second?.content, 'cached', reason: '应命中本地缓存');

      final refreshed = await cache.read(_keyA, refresh: true);
      expect(refreshed, isNull, reason: '强制刷新应回源并发现已删除');
    });

    test('invalidate 清空本地条目', () async {
      remote.seed(_keyA, 'cached', 'sha-c');
      await cache.read(_keyA);
      expect(await cache.localCount(), 1);
      await cache.invalidate(_keyA);
      expect(await cache.localCount(), 0);
    });

    test('索引存在但内容丢失时视为未命中并清理脏索引', () async {
      final kv = InMemoryKv();
      final blobs = InMemoryFileStore();
      final isolated = RepositoryCache(
        remote: remote,
        index: kv,
        blobs: blobs,
        diagnostics: diagnostics,
      );
      remote.seed(_keyA, 'content', 'sha-c');
      await isolated.read(_keyA);
      expect(kv.snapshot, isNotEmpty, reason: '索引应已建立');

      // 模拟磁盘损坏：内容丢失，且远端也已删除。
      for (final path in blobs.snapshot.keys.toList()) {
        await blobs.delete(path);
      }
      remote.store.remove(_keyA.encode());

      expect(await isolated.read(_keyA), isNull);
      expect(await isolated.localCount(), 0, reason: '脏索引必须被清理');
    });

    test('未绑定远端时读写必须显式失败（禁止静默丢数据）', () async {
      final unbound = RepositoryCache(diagnostics: diagnostics);
      await expectLater(unbound.read(_keyA), throwsA(isA<StateError>()));
    });
  });
}