/// L2 中枢级 · 下载后端的 **Web 实现**（把下载交给浏览器）。
///
/// ## 为什么是"交给浏览器"而不是"自己下载"
/// `background_downloader` **没有 Web 实现**（其平台清单只有 android / ios 等
/// 原生平台），而浏览器本身也**不给页面**：
/// - 后台任务与队列（页面关掉就没了）；
/// - 文件系统落盘（页面不能把响应体写进用户的下载目录）；
/// - 对下载过程的控制（暂停 / 继续 / 取消）。
///
/// 页面能做的只有一件事：**把最终地址交给浏览器的下载器**
/// （`window.open` 一类导航），剩下的由浏览器负责。
///
/// ## 由此产生的能力限制（如实标注，不假装支持）
/// | 能力 | Web 上 |
/// |------|--------|
/// | 保存路径 | **没有本地路径**：`savePath` 放下载地址本身 |
/// | 进度 / 速度 | **拿不到**（字节不经过页面）→ `total` 保持 0 |
/// | 暂停 / 继续 | **不可用**（浏览器下载不受页面控制） |
/// | 多连接分片 | **不可用**（见 `range_download_web.dart`） |
/// | 读回成品做 sha256 校验 / 导出到 SAF | **不可用**（成品在浏览器下载目录） |
/// | 带 `Authorization` 头的下载 | **不可行**：浏览器会剥离/不允许页面设置
///   跨域鉴权头 → 如实报失败（不用"看似成功"糊过去） |
///
/// ## 状态语义
/// 触发成功即置 `completed`；触发失败（含"需要鉴权头"与"被弹窗拦截"）
/// 置 `failed` 并给出**可读的原因**——永远不置"下载中"，
/// 因为没有页面可观测的下载过程。
library;

import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'ix_download.dart';

/// 按平台创建下载后端（Web）。
IxDownloadBackend createDownloadBackend() => WebDownloadBackend();

/// Web 下载后端：交给浏览器下载。
class WebDownloadBackend implements IxDownloadBackend {
  final StreamController<IxDownloadEvent> _events =
      StreamController<IxDownloadEvent>.broadcast();

  @override
  Stream<IxDownloadEvent> get events => _events.stream;

  @override
  bool get canReadLocalFile => false;

  @override
  bool get supportsRanged => false;

  @override
  bool get supportsPauseResume => false;

  /// Web 上没有本地落盘路径：返回**下载地址**本身。
  ///
  /// 界面拿它展示"文件在哪"——成品实际由浏览器写进它自己的下载目录，
  /// 位置由浏览器的设置决定，页面无从得知（也不编造一个假路径）。
  @override
  Future<String> pathFor(IxDownloadSpec spec) async => spec.url;

  @override
  Future<void> enqueue(IxDownloadSpec spec) async {
    final String? failure = await _handOffToBrowser(spec);
    // 用微任务派发终态：`enqueue` 返回之前，调用方（管理器）还没把快照登记好，
    // 同步发事件会因查不到 id 而被丢弃。
    scheduleMicrotask(() {
      if (_events.isClosed) {
        return;
      }
      _events.add(
        failure == null
            ? IxDownloadEvent.state(spec.id, IxDownloadStatus.completed)
            : IxDownloadEvent.state(
                spec.id,
                IxDownloadStatus.failed,
                error: failure,
              ),
      );
    });
  }

  // ── 浏览器下载不可由页面控制：以下操作一律为空操作。
  //    管理器会先查 `supportsPauseResume`，用户看到的提示是"本平台不支持"，
  //    而不是一个按下去毫无反应、却显示"已暂停"的假按钮。

  @override
  Future<void> pause(String id) async {}

  @override
  Future<void> resume(String id) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<int?> completedSize(String id) async => null;

  @override
  Future<String?> fileSha256(String id) async => null;

  @override
  Future<void> deleteFile(String id) async {}

  @override
  void dispose() {
    _events.close();
  }

  /// 把下载地址交给浏览器；返回 `null` 表示已成功触发，否则返回失败原因。
  Future<String?> _handOffToBrowser(IxDownloadSpec spec) async {
    final Uri? uri = Uri.tryParse(spec.url);
    if (uri == null) {
      return '下载地址非法';
    }
    final bool needsAuth = spec.headers.keys
        .any((String key) => key.toLowerCase() == 'authorization');
    if (needsAuth) {
      return 'Web 无法携带 Authorization 头下载（浏览器不允许页面设置跨域鉴权头）：'
          '请改用公开地址，或在浏览器里直接打开原始链接';
    }
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return '浏览器拒绝了下载（可能被弹窗拦截）';
      }
      return null;
    } catch (error) {
      return '触发浏览器下载失败：$error';
    }
  }
}
