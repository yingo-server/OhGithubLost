/// L2 中枢级 · 第一跳解析：把「需要认证的地址」换成一个**可直接下载的短期
/// 签名地址**。
///
/// ## 为什么需要它（实测结论，非推测）
/// GitHub 的三类二进制资源都是「**302 → 短期签名 URL**」的结构：
///
/// | 资源            | 第一跳                                | 302 目标                                |
/// |-----------------|---------------------------------------|-----------------------------------------|
/// | Release 附件    | `github.com/…/releases/download/…`   | `release-assets.githubusercontent.com`   |
/// | Action 运行日志 | `api.github.com/…/runs/{id}/logs`     | `results-receiver.actions.githubusercontent.com` |
/// | Action 构建产物 | `api.github.com/…/artifacts/{id}/zip` | `*.blob.core.windows.net`               |
///
/// **只有第一跳需要 `Authorization: Bearer`**；第二跳是绑定单对象、约 30 分钟
/// 有效的签名 URL，**不需要任何令牌**。所以只要在本地把第一跳走完、拿到
/// `Location`，后续（含交给第三方加速代理）都不必携带令牌 —— 令牌不出设备。
///
/// ## 顺带落地的安全约束
/// - **不跟随重定向**（`followRedirects = false`）：跳转目标由本方法显式校验，
///   而不是交给 SDK 的隐式行为。此前 `range_download.dart` 直接依赖
///   「Dart 跨域自动剥离 Authorization」这一未文档化行为来保证令牌不外泄。
/// - **跳转目标校验**：只允许 http/https，并拒绝回环 / 私网 / 链路本地地址
///   （含云元数据 `169.254.169.254`）。加速通道地址由用户填写，不校验就等于
///   允许设备被引导去探测内网。
library;

import 'dart:io';

/// 解析结果（失败时 [url] 为 `null`，调用方据此降级）。
class IxPresignResult {
  /// 创建结果。
  const IxPresignResult({
    required this.url,
    required this.redirected,
    this.statusCode,
    this.error,
  });

  /// 可直接请求的地址（`null` = 解析失败，调用方应回退到原始地址）。
  final String? url;

  /// 是否真的发生了跳转（`false` = 原始地址本身就是可下载的直链）。
  final bool redirected;

  /// 第一跳的 HTTP 状态码（便于诊断）。
  final int? statusCode;

  /// 失败原因（**如实携带，不静默**）。
  final String? error;

  /// 是否成功。
  bool get ok => url != null;

  @override
  String toString() => 'IxPresignResult(ok=$ok, redirected=$redirected, '
      'status=$statusCode, error=$error)';
}

/// 第一跳解析服务。
class IxPresign {
  /// 创建服务。
  ///
  /// [tokenProvider] 返回当前令牌明文（未登录返回 `null`；公开资源此时同样
  /// 能拿到签名地址，只是没有 Authorization 头）。
  /// [clientFactory] 仅供测试注入。
  IxPresign({
    required this.tokenProvider,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultClient;

  /// 令牌提供者。
  final Future<String?> Function() tokenProvider;

  final HttpClient Function() _clientFactory;

  static const Duration _connectTimeout = Duration(seconds: 20);
  static const Duration _receiveTimeout = Duration(seconds: 30);

  static HttpClient _defaultClient() {
    final HttpClient client = HttpClient();
    client.idleTimeout = const Duration(seconds: 3);
    client.connectionTimeout = _connectTimeout;
    client.userAgent = 'OhGithubLost';
    return client;
  }

  /// 把 [url] 解析成可直接下载的地址。
  ///
  /// 流程：请求第一跳（**不跟随重定向**）→ 若为 3xx 则取 `Location` 并校验 →
  /// 返回该地址；若第一跳本身就是 200，则原样返回（它已经是直链）。
  Future<IxPresignResult> resolve(String url) async {
    final Uri? source = Uri.tryParse(url);
    if (source == null ||
        (source.scheme != 'http' && source.scheme != 'https')) {
      return IxPresignResult(
        url: null,
        redirected: false,
        error: '非 http/https 地址',
      );
    }
    final HttpClient client = _clientFactory();
    try {
      final HttpClientRequest request =
          await client.getUrl(source).timeout(_connectTimeout);
      // ★ 显式不跟随：跳转目标由本类校验，不依赖 SDK 的隐式剥离行为。
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.persistentConnection = false;
      request.headers.set('accept', '*/*');
      final String? token = await tokenProvider();
      if (token != null && token.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $token');
      }
      final HttpClientResponse response =
          await request.close().timeout(_receiveTimeout);
      final int status = response.statusCode;
      if (status >= 300 && status < 400) {
        final String? location =
            response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          return IxPresignResult(
            url: null,
            redirected: true,
            statusCode: status,
            error: '3xx 但没有 Location',
          );
        }
        final String? target = safeRedirectTarget(location, source);
        if (target == null) {
          return IxPresignResult(
            url: null,
            redirected: true,
            statusCode: status,
            error: '跳转目标被拒绝（协议或主机不安全）',
          );
        }
        return IxPresignResult(
          url: target,
          redirected: true,
          statusCode: status,
        );
      }
      await response.drain<void>();
      // 200：第一跳本身就是直链，原样返回。
      if (status >= 200 && status < 300) {
        return IxPresignResult(
          url: url,
          redirected: false,
          statusCode: status,
        );
      }
      return IxPresignResult(
        url: null,
        redirected: false,
        statusCode: status,
        error: 'HTTP $status',
      );
    } on Object catch (error) {
      return IxPresignResult(url: null, redirected: false, error: '$error');
    } finally {
      client.close(force: true);
    }
  }

  /// 校验并解析跳转目标（相对地址按 [base] 补全）。
  static String? safeRedirectTarget(String location, Uri base) {
    final Uri? target = Uri.tryParse(location);
    if (target == null) {
      return null;
    }
    final Uri absolute = target.hasScheme ? target : base.resolveUri(target);
    if (absolute.scheme != 'http' && absolute.scheme != 'https') {
      return null;
    }
    if (isForbiddenHost(absolute.host)) {
      return null;
    }
    return absolute.toString();
  }

  /// 拒绝**回环 / 私网 / 链路本地 / 未指定 / 空**主机。
  ///
  /// 公开理由：加速通道地址由用户填写，而签名地址来自 302；不校验就等于给了
  /// 一条「让设备去请求任意内网地址」的路。云环境元数据服务
  /// （`169.254.169.254`）就在链路本地段里。
  static bool isForbiddenHost(String host) {
    final String h = host.trim().toLowerCase();
    if (h.isEmpty || h == 'localhost' || h.endsWith('.localhost')) {
      return true;
    }
    if (h == '::1' || h == '0:0:0:0:0:0:0:1') {
      return true;
    }
    // IPv6 唯一本地（fc00::/7）与链路本地（fe80::/10）。
    if (h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80:')) {
      return true;
    }
    final RegExpMatch? m =
        RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
    if (m == null) {
      return false; // 域名：不在这里猜 IP。
    }
    final int a = int.parse(m.group(1)!);
    final int b = int.parse(m.group(2)!);
    if (a == 0 || a == 127) {
      return true; // 未指定 / 回环
    }
    if (a == 10) {
      return true; // 私网 10/8
    }
    if (a == 172 && b >= 16 && b <= 31) {
      return true; // 私网 172.16/12
    }
    if (a == 192 && b == 168) {
      return true; // 私网 192.168/16
    }
    if (a == 169 && b == 254) {
      return true; // 链路本地，含云元数据
    }
    return false;
  }

  /// 把 JSON 里的摘要字段规整成小写十六进制；不是 sha256 或缺失则返回 `null`。
  ///
  /// GitHub Release 资产的 `digest` 形如 `sha256:ab12…`；私有仓库与旧资产
  /// 可能为 `null` —— 那就**如实当作未提供**，绝不假装验过。
  static String? normalizeDigest(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    final String text = raw.trim().toLowerCase();
    final int colon = text.indexOf(':');
    final String algo = colon < 0 ? text : text.substring(0, colon);
    if (algo != 'sha256') {
      return null;
    }
    final String hex = colon < 0 ? '' : text.substring(colon + 1);
    if (hex.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
      return null;
    }
    return hex;
  }
}