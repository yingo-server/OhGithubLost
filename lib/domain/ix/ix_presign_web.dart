/// L2 中枢级 · 第一跳解析的 **Web 实现**（无法预签名，如实返回原地址）。
///
/// ## 为什么 Web 上做不了预签名
/// 第一跳的价值是"读出不跟随重定向时的 `Location`"。但浏览器里：
/// - `fetch` 默认**自动跟随**重定向，且在这个过程中第二次请求**不会**带上
///   我们设置的 `Authorization` 跨域头（第三方源收不到令牌）——
///   也就是说浏览器根本不让页面参与"第一跳 → 第二跳"的分段；
/// - 即使强制 `redirect: 'manual'`，响应也是 **opaque-redirect**：
///   `status === 0`、`headers` 为空，**读不到 `Location`**（这是同源策略的
///   明确规定，不是实现缺陷）。
///
/// 结论：Web 上**拿不到签名地址**。因此这里如实返回
/// `IxPresignResult(url: 原地址, redirected: false)` —— 语义是"解不出签名，
/// 请按无签名处理"。调用方据此走"直接请求原地址"的路径即可。
///
/// ★ 安全红线：**绝不**改成"跟随重定向去取内容"。那样等于把带令牌的第一跳
///   与受保护内容一次性交给浏览器，绕过了"令牌只用在第一跳"的设计；
///   而且跨域重定向后浏览器会剥离 Authorization，最后照样拿不到内容——
///   既破坏安全边界，又解决不了问题。
library;

import 'ix_presign.dart';

/// 第一跳探测（Web：无法预签名）。
abstract final class IxPresignProbe {
  /// 直接返回原地址，并标记 `redirected: false`（"未解出签名"）。
  static Future<IxPresignResult> resolve(
    String url,
    Future<String?> Function() tokenProvider,
  ) async =>
      IxPresignResult(url: url, redirected: false);
}
