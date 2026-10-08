/// [browser_notify.dart] 的 **Web 实现**：直接使用浏览器的 `Notification`。
///
/// ## 只用 `dart:js_interop`
/// 不引入 `package:web`（依赖清单纪律，见 `web_install_web.dart` 的说明）。
/// 选项对象用 `jsify()` 把 Dart `Map` 直接转成 JS 对象，避免再开一个 unsafe
/// 转义口。
///
/// ## 诚实原则
/// - 浏览器没有 `Notification` → `unsupported`（**不是** `denied`）；
/// - 申请授权返回什么就报什么；
/// - 构造通知抛异常 → 返回 `false`（"没发出去"），绝不假装成功。
library;

import 'dart:js_interop';

import 'package:flutter/foundation.dart';

/// 浏览器的 `Notification` 构造器视图。
///
/// 名称用 `@JS('Notification')` 映射到全局构造器；`external static` 成员对应
/// `Notification.permission` / `Notification.requestPermission()`。
@JS('Notification')
extension type _Notification._(JSObject _) implements JSObject {
  /// `new Notification(title, options)`。
  external factory _Notification(String title, JSObject options);

  /// `Notification.permission`：`granted` / `denied` / `default`。
  external static String get permission;

  /// `Notification.requestPermission()` → `Promise<string>`。
  external static JSPromise<JSString> requestPermission();
}

/// 浏览器是否提供通知能力。
///
/// 判定方式是**直接读一次** `Notification.permission`（见
/// [ogLBrowserNotifyPermission]）：读不到（该浏览器没有 `Notification` 全局，
/// 例如 iOS Safari 16.4 之前）就如实报"不支持"——**不是**"已拒绝"。
bool ogLBrowserNotifySupported() =>
    ogLBrowserNotifyPermission() != 'unsupported';

/// 当前授权状态；读不到一律 `unsupported`（**绝不谎报为已拒绝**）。
String ogLBrowserNotifyPermission() {
  try {
    return _Notification.permission;
  } catch (error) {
    debugPrint('OGL 浏览器通知：读取授权状态失败（$error）');
    return 'unsupported';
  }
}

/// 真实申请一次授权（浏览器会弹自己的授权条）。
Future<String> ogLBrowserNotifyRequest() async {
  try {
    final JSString value = await _Notification.requestPermission().toDart;
    return value.toDart;
  } catch (error) {
    debugPrint('OGL 浏览器通知：申请授权失败（$error）');
    return 'unsupported';
  }
}

/// 发送一条浏览器通知。返回是否**确实**发出。
bool ogLBrowserNotifyShow(String title, String? body) {
  try {
    final JSObject options = <String, Object?>{
      if (body != null && body.isNotEmpty) 'body': body,
    }.jsify()! as JSObject;
    _Notification(title, options);
    return true;
  } catch (error) {
    debugPrint('OGL 浏览器通知：发送失败（$error）');
    return false;
  }
}
