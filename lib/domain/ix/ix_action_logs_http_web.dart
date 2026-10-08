/// L2 中枢级 · Actions 日志的**字节获取**（Web，`package:http` 浏览器实现）。
///
/// ## 与原生侧的差异（如实说明）
/// - **没有连接策略**：浏览器管理连接池，`persistentConnection` 之类的开关
///   在 Web 上不适用，因此这里不设（也不假装能设）；
/// - **超时**：只有整段超时（浏览器不暴露"连接"与"接收"两段）；
/// - **重定向**：`fetch` 自动跟随（GitHub 的 logs 接口是 302 → 签名 zip），
///   跳数上限由浏览器决定（通常 20 跳）；
/// - **CORS**：GitHub API 对浏览器开放 CORS，因此带 `Authorization` 的
///   preflight 能通过。若对方不允许跨域，浏览器会**统一**报一次网络错误，
///   页面无法区分它是 CORS 还是断网——本实现如实转述浏览器给出的消息，
///   不臆造"DNS 失败"之类的结论。
///
/// 只在 Web 构建里参与编译；原生对应文件是 `ix_action_logs_http_io.dart`。
library;

import 'package:http/http.dart' as http;

import 'ix_action_logs.dart';

/// 日志字节获取（Web）。
abstract final class IxActionLogsHttp {
  static const Duration _timeout = Duration(minutes: 5);

  /// 发起 GET，返回响应字节；非 2xx/3xx 抛 [IxActionLogsException]。
  static Future<List<int>> fetchBytes(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final http.Client client = http.Client();
    try {
      final http.Response response =
          await client.get(uri, headers: headers).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw IxActionLogsException(
          '拉取日志失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      return response.bodyBytes;
    } on IxActionLogsException {
      rethrow;
    } on Object catch (error) {
      throw IxActionLogsException(
        '拉取日志异常：$error'
        '（Web 端不区分 DNS / TLS / CORS，可能需要对方允许跨域访问）',
      );
    } finally {
      client.close();
    }
  }
}
