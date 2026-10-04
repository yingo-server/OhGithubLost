/// L3 展示级 · 异步加载收敛（控制器 + 视图）。
///
/// ## 为什么需要它
/// 每个页面都要面对同一组问题：**加载中、空、出错、有数据、刷新失败**。
/// 若每页各写 `isLoading` + `error` + `data` 三个变量，就会出现：
/// - 有的页面空列表和加载中长得一样（用户以为坏了）；
/// - 有的页面刷新失败后把旧数据也丢了（明明还有内容可看）；
/// - 有的页面错了不显示原因（"点了没反应"）。
///
/// 所以把状态收敛到一个 [AsyncController]，把四态渲染收敛到 [AsyncView]：
/// ```
/// 首次加载中 → 转圈
/// 失败（无数据）→ 原因 + 重试（错误必须可见）
/// 空结果 → 明确的空态文案（与"加载中"严格区分）
/// 有数据 → 内容；若带"刷新失败"，顶部提示但**保留旧数据**
/// ```
library;

import 'package:flutter/material.dart';

import '../i18n/og_l_i18n.dart';
import 'animations.dart';
import 'error_surface.dart';

/// 取 `shell` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('shell', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 通用异步控制器：加载 / 刷新 / 重试，并发抑制、失败保留旧数据。
class AsyncController<T> extends ChangeNotifier {
  /// 创建控制器。
  AsyncController({
    required this.label,
    required this.loader,
    required this.isEmpty,
  });

  /// 中文名（进日志与错误文案）。
  final String label;

  /// 加载函数。
  final Future<T> Function() loader;

  /// 判定"空结果"的规则。
  final bool Function(T value) isEmpty;

  T? _data;
  String? _error;
  bool _empty = false;
  bool _loading = false;
  bool _everLoaded = false;

  /// 数据（可能为 `null`）。
  T? get data => _data;

  /// 最近一次错误（**不吞**）。
  String? get error => _error;

  /// 是否正在请求。
  bool get isLoading => _loading;

  /// 首次加载中（尚无任何可展示内容）。
  bool get isFirstLoading => _data == null && _error == null && !_empty;

  /// 加载成功但结果为空（与"加载中"严格区分）。
  bool get isEmptyResult => _data != null && _empty;

  /// 失败原因（无数据可展示时；**不允许只显示"出错了"**）。
  String? get failureMessage =>
      (!_loading && _data == null && _error != null) ? _error : null;

  /// 刷新失败（此时旧数据仍然可看）。
  String? get softError => _data != null ? _error : null;

  /// 首次进入时触发一次加载（已加载过则不重复）。
  Future<void> loadIfNeeded() async {
    if (_everLoaded || _loading) {
      return;
    }
    await load();
  }

  /// 加载 / 刷新（**并发抑制**：上一次没回来之前不再发第二次）。
  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;
    notifyListeners();

    try {
      final T value = await loader();
      _data = value;
      _empty = isEmpty(value);
      _error = null;
      OgLAppLog.instance.result(_t('loading'), _t('done', {'label': label}), _summarize(value));
    } catch (error) {
      _error = _describe(error);
      OgLAppLog.instance.add(
        _t('loading'),
        _error!,
        severity: OgLNoticeSeverity.critical,
      );
    } finally {
      _loading = false;
      _everLoaded = true;
      notifyListeners();
    }
  }

  /// 清掉错误提示（用户已读）。
  void dismissError() {
    if (_error == null) {
      return;
    }
    _error = null;
    notifyListeners();
  }

  /// 清空已加载数据与错误（**切换数据维度**时使用）。
  ///
  /// 典型场景：仓库浏览器切换目录。若不清空，网络还没返回时界面会继续展示
  /// **上一个目录**的文件——挂在新路径下看就是"撕裂"。清空后进入明确的
  /// 加载态，宁可转圈也不展示错误数据。
  void reset() {
    _data = null;
    _error = null;
    _empty = false;
    _loading = false;
    _everLoaded = false;
    notifyListeners();
  }

  /// 把加载结果压成一句人话（列表给条数、文本给长度、其它给类型）。
  String _summarize(Object? value) {
    if (value == null) {
      return _t('empty');
    }
    if (value is List<Object?>) {
      return _t('countItems', {'count': value.length});
    }
    if (value is String) {
      return _t('countChars', {'count': value.length});
    }
    if (value is Map<Object?, Object?>) {
      return _t('countKeys', {'count': value.length});
    }
    return value.runtimeType.toString();
  }

  /// 错误 → 人话（只暴露"人话"，不让异常栈糊到用户脸上）。
  String _describe(Object error) {
    final String text = error.toString();
    if (text.startsWith('Exception: ')) {
      return _t('failedWith', {'label': label, 'text': text.substring(11)});
    }
    return _t('failedParen', {'label': label, 'text': text});
  }
}

/// 把 [AsyncController] 的四态渲染成 Material 组件（页面不再自己判状态）。
class AsyncView<T> extends StatelessWidget {
  /// 创建视图。
  const AsyncView({
    required this.controller,
    required this.builder,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyText,
    this.emptyAction,
    this.fill = true,
    super.key,
  });

  /// 控制器。
  final AsyncController<T> controller;

  /// 有数据时的内容构造器。
  final Widget Function(BuildContext context, T data) builder;

  /// 空态图标。
  final IconData emptyIcon;

  /// 空态文案。
  final String? emptyText;

  /// 空态动作（可选）。
  final Widget? emptyAction;

  /// 是否占满父级剩余空间（放在 `Expanded` 里时为 true；
  /// 嵌在 `ListView` 等无界高度场景时为 false）。
  final bool fill;

  /// 在「加载 / 空 / 错误」之间做淡入淡出；档位 0 时直接返回子控件。
  ///
  /// 只包这三种以 `Center` 为根的状态，避免把可能含 `Expanded` 的数据态
  /// 放进 `AnimatedSwitcher` 的 `Stack` 里造成无界高度问题。
  Widget _animatedState(BuildContext context, String state, Widget child) {
    if (!OgLAnim.enabled(context)) {
      return child;
    }
    return AnimatedSwitcher(
      duration: OgLAnim.fast(context),
      child: KeyedSubtree(key: ValueKey<String>(state), child: child),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) {
          final T? data = controller.data;
          if (data == null) {
            final String? failure = controller.error;
            if (failure != null && !controller.isLoading) {
              return _animatedState(
                context,
                'error',
                _ErrorPane(message: failure, onRetry: controller.load),
              );
            }
            return _animatedState(
              context,
              'loading',
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }
          if (controller.isEmptyResult) {
            return _animatedState(
              context,
              'empty',
              _EmptyPane(
                icon: emptyIcon,
                text: emptyText ?? _t('noContent'),
                action: emptyAction,
              ),
            );
          }
          final String? soft = controller.softError;
          if (soft == null) {
            return builder(context, data);
          }
          return Column(
            children: <Widget>[
              _SoftErrorBar(message: soft, onDismiss: controller.dismissError),
              if (fill)
                Expanded(child: builder(context, data))
              else
                builder(context, data),
            ],
          );
        },
      );
}

/// 失败面板：原因 + 重试（错误不许无声消失）。
class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 40, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child:  Text(_t('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态面板：图标 + 一句话 + 可选动作。
class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: scheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 软错误条：刷新失败时保留旧数据，只在上方提示。
class _SoftErrorBar extends StatelessWidget {
  const _SoftErrorBar({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: scheme.onErrorContainer),
              tooltip: _t('ignore'),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}