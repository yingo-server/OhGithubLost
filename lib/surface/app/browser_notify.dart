/// L3 展示级 · **浏览器通知门面**（条件导入选实现）。
///
/// ## 为什么单独一个门面
/// 浏览器里的通知权限与发送**只有** `Notification` 这一条路（`dart:io` 的
/// `HttpClient` / 插件都不在），而原生平台走的是 `permission_handler` +
/// `flutter_local_notifications`。两边语义完全不同，因此用最小门面隔开：
/// - Web：`browser_notify_web.dart`（`dart:js_interop`）；
/// - 非 Web：`browser_notify_io.dart`（空实现，不引用任何 Web API）。
///
/// ## 诚实原则
/// 所有函数**只报告真实结果**：浏览器不支持就说 `unsupported`，
/// 发送失败就返回 `false`，绝不把"没做到"报成"已发送"。
library;

import 'browser_notify_io.dart'
    if (dart.library.js_interop) 'browser_notify_web.dart' as impl;

/// 当前环境是否提供浏览器通知能力（非 Web 恒为 `false`）。
bool ogLBrowserNotifySupported() => impl.ogLBrowserNotifySupported();

/// 当前通知授权状态：`granted` / `denied` / `default` / `unsupported`。
String ogLBrowserNotifyPermission() => impl.ogLBrowserNotifyPermission();

/// **真实申请**一次通知授权（浏览器会弹自己的授权条）。返回申请后的状态。
Future<String> ogLBrowserNotifyRequest() => impl.ogLBrowserNotifyRequest();

/// 发送一条浏览器通知；返回是否**确实**发出（不支持 / 未授权 / 失败 = `false`）。
bool ogLBrowserNotifyShow(String title, String? body) =>
    impl.ogLBrowserNotifyShow(title, body);
