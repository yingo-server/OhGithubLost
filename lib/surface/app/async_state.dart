/// L3 展示级 · 交互逻辑：统一的异步状态模型。
///
/// ## 为什么需要它
/// 每个页面都要面对同一组问题：**加载中、空、出错、有数据、正在刷新**。
/// 如果每个页面自己写 `isLoading` + `error` + `data` 三个变量，
/// 就会出现：
/// - 有的页面错了不显示原因（"点了没反应"）；
/// - 有的页面空列表和加载中长得一样（用户以为坏了）；
/// - 有的页面刷新失败后把旧数据也丢了（**明明还有内容可看**）。
///
/// 所以这里把状态收敛成一个**四态枚举 + 一个泛型容器**：
/// ```
/// idle ──load()──▶ loading ──┬─▶ ready（有数据）
///                            ├─▶ empty（确实没有数据）
///                            └─▶ failed（有原因、可重试）
/// ```
///
/// ## 两条硬规则
/// 1. **刷新失败不得丢掉已有数据**：`refreshFailed` 与 `failed` 是两件事，
///    前者保留上一次的 ready 数据并附带错误提示；
/// 2. **失败必须有原因**：`OgLAsync.failed` 一律携带 `message`，
///    界面不允许只显示"出错了"。
library;

import 'package:flutter/foundation.dart';

/// 异步数据的四态。
enum OgLAsyncPhase {
  /// 尚未开始。
  idle,

  /// 首次加载中（无任何数据可显示）。
  loading,

  /// 已有数据。
  ready,

  /// 加载成功但结果为空（**与 ready 区分**：空要有空的样子）。
  empty,

  /// 失败且无数据可显示。
  failed,
}

/// 异步状态容器。
@immutable
class OgLAsync<T> {
  /// 创建状态。
  const OgLAsync._({
    required this.phase,
    this.data,
    this.message,
    this.refreshError,
    this.updatedAt,
  });

  /// 尚未开始。
  const OgLAsync.idle()
      : phase = OgLAsyncPhase.idle,
        data = null,
        message = null,
        refreshError = null,
        updatedAt = null;

  /// 加载中（可携带上一次的数据，用于"刷新时保留内容"）。
  const OgLAsync.loading({T? previous})
      : phase = OgLAsyncPhase.loading,
        data = previous,
        message = null,
        refreshError = null,
        updatedAt = null;

  /// 成功。
  OgLAsync.ready(T value)
      : this._(
          phase: OgLAsyncPhase.ready,
          data: value,
          updatedAt: DateTime.now(),
        );

  /// 成功但为空。
  OgLAsync.empty()
      : this._(phase: OgLAsyncPhase.empty, updatedAt: DateTime.now());

  /// 失败（无数据可显示）。
  OgLAsync.failed(String message)
      : this._(phase: OgLAsyncPhase.failed, message: message);

  /// 带数据的类型标注（用于 `const` 构造之外的场景）。
  const OgLAsync.data(T value)
      : phase = OgLAsyncPhase.ready,
        data = value,
        message = null,
        refreshError = null,
        updatedAt = null;

  /// 当前阶段。
  final OgLAsyncPhase phase;

  /// 数据（`loading` 时可能是上一次的数据）。
  final T? data;

  /// 失败原因（**不允许为空**：界面不能只说"出错了"）。
  final String? message;

  /// 刷新失败的原因（**此时 `data` 仍然可用**，界面应保留内容并提示）。
  final String? refreshError;

  /// 数据时间戳（用于"刚刚更新 / 5 分钟前"这类提示）。
  final DateTime? updatedAt;

  /// 是否正在忙（首次加载或刷新）。
  bool get isBusy =>
      phase == OgLAsyncPhase.loading ||
      (phase == OgLAsyncPhase.ready && refreshError == null && data == null);

  /// 是否还没有任何可显示的内容。
  bool get hasNothing => phase == OgLAsyncPhase.idle || phase == OgLAsyncPhase.loading;

  /// 是否可以展示数据。
  bool get hasData =>
      data != null &&
      (phase == OgLAsyncPhase.ready ||
          phase == OgLAsyncPhase.loading ||
          phase == OgLAsyncPhase.empty);

  /// 进入加载态：**保留旧数据**（刷新时界面不该闪成空白）。
  OgLAsync<T> toLoading() => OgLAsync<T>.loading(previous: data);

  /// 用新数据落定。
  OgLAsync<T> settle(T value, {required bool Function(T value) isEmpty}) =>
      isEmpty(value) ? OgLAsync<T>.empty() : OgLAsync<T>.ready(value);

  /// 出错落定。
  ///
  /// 有旧数据 ⇒ 记进 [refreshError]（数据仍可看）；没有 ⇒ 进入 `failed`。
  OgLAsync<T> fail(String reason) => hasData
      ? OgLAsync<T>._(
          phase: phase,
          data: data,
          refreshError: reason,
          updatedAt: updatedAt,
        )
      : OgLAsync<T>.failed(reason);

  /// 复制（清除刷新错误）。
  OgLAsync<T> cleared() => OgLAsync<T>._(
        phase: phase,
        data: data,
        updatedAt: updatedAt,
      );

  @override
  String toString() => 'OgLAsync(${phase.name}'
      '${data == null ? '' : ', data=${data.runtimeType}'}'
      '${message == null ? '' : ', msg=$message'}'
      '${refreshError == null ? '' : ', refreshErr=$refreshError'})';
}

/// 可复用的异步控制器：把"加载 / 刷新 / 重试"固化下来。
///
/// 页面只提供 `loader`，其余（并发抑制、错误归类、保留旧数据）都在这里处理。
class OgLAsyncController<T> extends ChangeNotifier {
  /// 创建控制器。
  OgLAsyncController({
    required this.loader,
    required bool Function(T value) isEmpty,
    this.label = '数据',
  }) : _isEmpty = isEmpty;

  /// 加载函数。
  final Future<T> Function() loader;

  /// 判定"空"的规则。
  final bool Function(T value) _isEmpty;

  /// 中文名（进错误文案）。
  final String label;

  OgLAsync<T> _state = const OgLAsync<T>.idle();
  bool _inFlight = false;

  /// 当前状态。
  OgLAsync<T> get state => _state;

  /// 是否正在请求。
  bool get isBusy => _inFlight;

  /// 首次加载（已有数据时不做事，避免无谓请求）。
  Future<void> loadIfNeeded() async {
    if (_state.phase == OgLAsyncPhase.idle) {
      await load();
    }
  }

  /// 加载 / 刷新。
  ///
  /// **并发抑制**：上一次没回来之前不再发第二次——否则慢网络下会打出
  /// 一串重复请求，返回顺序还可能颠倒，界面最后显示的是"旧结果"。
  Future<void> load() async {
    if (_inFlight) {
      return;
    }
    _inFlight = true;
    _state = _state.toLoading();
    notifyListeners();

    try {
      final value = await loader();
      _state = _state.settle(value, isEmpty: _isEmpty);
    } catch (error) {
      _state = _state.fail(_describe(error));
    } finally {
      _inFlight = false;
      notifyListeners();
    }
  }

  /// 本地改动后直接落定（避免为了刷新再跑一次网络）。
  void settleWith(T value) {
    _state = _state.settle(value, isEmpty: _isEmpty);
    notifyListeners();
  }

  /// 清掉刷新错误提示（用户点了"知道了"）。
  void dismissRefreshError() {
    if (_state.refreshError != null) {
      _state = _state.cleared();
      notifyListeners();
    }
  }

  String _describe(Object error) {
    final text = error.toString();
    // 只暴露"人话"，不让异常栈糊到用户脸上。
    if (text.startsWith('Exception: ')) {
      return '$label加载失败：${text.substring(11)}';
    }
    return '$label加载失败（$text）';
  }
}
