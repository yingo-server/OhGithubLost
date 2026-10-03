/// L3 展示级 · 全局错误呈现层：**错误捕获 + 弹窗/横幅抛出**。
///
/// ## 它在兜什么
/// 商业级应用的基本底线：**任何错误都不允许无声消失**。
/// 本文件把三类错误统一收口到"用户可见"：
/// 1. Flutter 框架异常（构建/布局/绘制）→ `critical` 弹窗；
/// 2. 平台/异步未捕获异常 → `critical` 弹窗；
/// 3. 业务层主动上报的告警（网络降级、磁盘清理失败等）→ 横幅。
///
/// ## 为什么是"中心 + 宿主"两级
/// - [OgLNoticeCenter] 是**单例**：任何层（包括没有 `BuildContext` 的
///   底座/中枢代码）都能上报，不依赖 UI 树；
/// - [OgLNoticeHost] 挂在 `MaterialApp.builder` 里：只有它持有
///   `Navigator` / `ScaffoldMessenger`，负责把通知真正"抛"到屏幕上。
///
/// 弹窗用 `AlertDialog`（阻塞式、必须被阅读——适用于异常）；
/// 普通告警用 `SnackBar`（不打断操作）。
library;

import 'package:flutter/material.dart';
import '../../kernel/boot/trust_warnings.dart';
import '../../kernel/diagnostics.dart';
import '../../kernel/log/og_l_log_file.dart';

/// 通知严重级别。
enum OgLNoticeSeverity {
  /// 提示（横幅展示）。
  info,

  /// 告警（横幅展示）。
  warning,

  /// 严重（**弹窗**展示，必须被用户看到）。
  critical,
}

/// 一条用户可见的通知。
class OgLNotice {
  /// 创建通知。
  const OgLNotice({
    required this.title,
    this.detail,
    this.severity = OgLNoticeSeverity.warning,
  });

  /// 标题（一行说清发生了什么）。
  final String title;

  /// 详情（可为空；弹窗里可选文本复制）。
  final String? detail;

  /// 严重级别。
  final OgLNoticeSeverity severity;
}

/// 全局通知中心（单例）。
///
/// 线程模型：全部在 UI 隔离区（Flutter 主 isolate）内使用；
/// 队列有上限，防止"异常风暴"把内存打满（保留最早与最新的可读性折中：
/// 超限时丢弃最旧的低级别通知）。
class OgLNoticeCenter extends ChangeNotifier {
  OgLNoticeCenter._();

  /// 单例。
  static final OgLNoticeCenter instance = OgLNoticeCenter._();

  /// 队列上限（超过时**优先**丢弃最旧的 info/warning；
  /// 极端情况（队列里全是 critical）下丢弃最旧的一条——保证内存有界）。
  static const int maxPending = 50;

  final List<OgLNotice> _pending = <OgLNotice>[];
  final List<OgLNotice> _history = <OgLNotice>[];

  /// 历史通知（最新在前，供通知中心页展示）。
  List<OgLNotice> get history => List<OgLNotice>.unmodifiable(_history);

  /// 待展示队列（只读视图）。
  List<OgLNotice> get pending => List<OgLNotice>.unmodifiable(_pending);

  /// 上报一条通知。
  ///
  /// 去重：相同的 `title + detail` 已在队列里时不再重复入队
  /// （避免同一个异常每帧上报刷屏）。
  void report({
    required String title,
    String? detail,
    OgLNoticeSeverity severity = OgLNoticeSeverity.warning,
  }) {
    // 先落盘：通知可能因为"正在弹窗"而延后展示，但**绝不允许**丢失。
    OgLLogFile.line(
      '通知',
      detail == null || detail.isEmpty ? title : '$title：$detail',
      level: severity == OgLNoticeSeverity.critical
          ? 'ERR'
          : severity == OgLNoticeSeverity.warning
              ? 'WARN'
              : 'INFO',
    );
    for (final existing in _pending) {
      if (existing.title == title && existing.detail == detail) {
        return;
      }
    }
    if (_pending.length >= maxPending) {
      final dropIndex = _pending.indexWhere(
        (OgLNotice n) => n.severity != OgLNoticeSeverity.critical,
      );
      _pending.removeAt(dropIndex == -1 ? 0 : dropIndex);
    }
    final notice = OgLNotice(title: title, detail: detail, severity: severity);
    _pending.add(notice);
    _history.insert(0, notice);
    while (_history.length > 200) {
      _history.removeLast();
    }
    notifyListeners();
  }

  /// 取走最早的一条（宿主消费用）。
  OgLNotice? take() {
    if (_pending.isEmpty) {
      return null;
    }
    return _pending.removeAt(0);
  }
}

/// 应用级日志环（surface 层）：记录用户操作与**原始错误**，供「关于页」展示。
///
/// 与内核日志（`KernelReport.logTail`）互补：
/// 内核管"启动与治理"，这里管"用户行为与网络/认证失败"。
class OgLAppLog extends ChangeNotifier {
  OgLAppLog._();

  /// 单例。
  static final OgLAppLog instance = OgLAppLog._();

  /// 条目上限（环形丢弃最旧）。
  static const int maxEntries = 2000;

  final List<OgLAppLogEntry> _entries = <OgLAppLogEntry>[];

  /// 全部条目（**最新在前**，方便直接看）。
  List<OgLAppLogEntry> get entries =>
      List<OgLAppLogEntry>.unmodifiable(_entries.reversed.toList());

  /// 追加一条。
  ///
  /// **同时写入磁盘**（`OgLLogFile`）：内存只负责"关于页里能翻"，
  /// 磁盘负责"进程死了也还在"。
  void add(
    String area,
    String message, {
    OgLNoticeSeverity severity = OgLNoticeSeverity.info,
  }) {
    _entries.add(OgLAppLogEntry(
      at: DateTime.now(),
      area: area,
      message: message,
      severity: severity,
    ));
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    notifyListeners();
    OgLLogFile.line(
      area,
      message,
      level: severity == OgLNoticeSeverity.critical
          ? 'ERR'
          : severity == OgLNoticeSeverity.warning
              ? 'WARN'
              : 'INFO',
    );
  }

  /// 记录**成功的结果**（用户明确要求：不要只记错误）。
  ///
  /// 例：`result('仓库', '拉取议题', '30 条')` → 落盘为 `✔ 拉取议题：30 条`。
  void result(String area, String what, [String? detail]) {
    final String suffix = (detail == null || detail.isEmpty) ? '' : '：$detail';
    add(area, '✔ $what$suffix');
  }

  /// 记录**一个步骤的开始**（与 [result] 配对，形成"开始→结果"两行）。
  void step(String area, String what) {
    add(area, '▶ $what');
  }
}

/// 一条应用日志。
class OgLAppLogEntry {
  /// 创建条目。
  const OgLAppLogEntry({
    required this.at,
    required this.area,
    required this.message,
    required this.severity,
  });

  /// 时间。
  final DateTime at;
  /// 区域（认证 / 仓库 / …）。
  final String area;
  /// 正文（含原始异常与堆栈）。
  final String message;
  /// 级别。
  final OgLNoticeSeverity severity;

  /// 展示格式：`[HH:mm:ss][区域] 正文`。
  String toDisplay() {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final s = at.second.toString().padLeft(2, '0');
    return '[$h:$m:$s][$area] $message';
  }
}

/// 宿主：把通知中心里的条目渲染成弹窗 / 横幅。
///
/// 挂在 `MaterialApp.builder` —— 这样**整棵应用树**里的错误都能抛到这里。
///
/// **为什么需要 [navigatorKey]**：`builder` 层的 context 位于 Navigator
/// **之上**（Navigator 是 builder 的 child），`showDialog` 从该 context
/// 向上查找 Navigator 会直接报错。因此 critical 弹窗必须借应用根
/// Navigator 的 context 来完成；未提供（或尚未就绪）时降级为横幅，绝不静默。
class OgLNoticeHost extends StatefulWidget {
  /// 创建宿主。
  const OgLNoticeHost({
    required this.child,
    this.navigatorKey,
    super.key,
  });

  /// 被包裹的应用内容。
  final Widget child;

  /// 应用根 Navigator 的 key（可为 `null`：此时 critical 降级为横幅）。
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<OgLNoticeHost> createState() => _OgLNoticeHostState();
}

class _OgLNoticeHostState extends State<OgLNoticeHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    OgLNoticeCenter.instance.addListener(_drain);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    OgLNoticeCenter.instance.removeListener(_drain);
    super.dispose();
  }

  void _drain() {
    if (!mounted || _showing) {
      return;
    }
    final notice = OgLNoticeCenter.instance.take();
    if (notice == null) {
      return;
    }
    _showing = true;
    if (notice.severity == OgLNoticeSeverity.critical) {
      _presentCritical(notice);
    } else {
      _presentAmbient(notice);
    }
  }

  /// 严重：弹窗（必须被阅读）。
  ///
  /// 弹窗必须借**应用根 Navigator** 的 context——宿主自身所在的 `builder`
  /// 层在 Navigator 之上，直接就地 `showDialog` 会抛
  /// "does not include a Navigator"。根 Navigator 尚未就绪时
  /// 降级为横幅（仍然可见）并留盘，绝不静默。
  void _presentCritical(OgLNotice notice) {
    final BuildContext? navContext = widget.navigatorKey?.currentContext;
    if (navContext == null) {
      OgLLogFile.line(
        '通知',
        '根 Navigator 未就绪，critical 降级为横幅：${notice.title}',
        level: 'WARN',
      );
      _presentAmbient(notice);
      return;
    }
    showDialog<void>(
      context: navContext,
      builder: (BuildContext context) => AlertDialog(
        title: Text(notice.title),
        content: notice.detail == null || notice.detail!.isEmpty
            ? null
            : SelectableText(notice.detail!),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    ).whenComplete(() {
      if (!mounted) {
        return;
      }
      _showing = false;
      // 继续消费队列（可能还有更多）。
      WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    });
  }

  /// 一般：横幅（不打断操作）。
  void _presentAmbient(OgLNotice notice) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = notice.detail == null || notice.detail!.isEmpty
        ? notice.title
        : '${notice.title}：${notice.detail}';
    messenger?.showSnackBar(SnackBar(content: Text(text)));
    _showing = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 把内核诊断的 **warn / error** 转发到通知中心。
///
/// 用户要求：**不允许静默降级** —— 任何降级 / 异常都必须以"带事件码"的通知
/// 形式可见（error → 严重级，走弹窗；warn → 告警级，走横幅）。
class OgLDiagnosticsNoticeSink implements KernelLogSink {
  /// 创建接收方。
  const OgLDiagnosticsNoticeSink();

  @override
  void onLog(KernelLogEntry entry) {
    final bool isError = entry.level == KernelLogLevel.error;
    final bool isWarn = entry.level == KernelLogLevel.warn;
    if (!isError && !isWarn) {
      return;
    }
    OgLNoticeCenter.instance.report(
      title: entry.message,
      detail: entry.code == null ? entry.tag : '${entry.tag} · ${entry.code}',
      severity: isError ? OgLNoticeSeverity.critical : OgLNoticeSeverity.warning,
    );
  }
}

/// 把引导层信任告警转发到通知中心（`docs/BOOT.md` 要求"必须 UI 触达"）。
class OgLTrustNoticeSink implements TrustWarningSink {
  /// 创建接收方。
  const OgLTrustNoticeSink();

  @override
  void onWarning(BootTrustWarning warning) {
    OgLNoticeCenter.instance.report(
      title: warning.message,
      detail: warning.subject,
      severity: warning.severity == TrustSeverity.danger
          ? OgLNoticeSeverity.critical
          : OgLNoticeSeverity.warning,
    );
  }
}