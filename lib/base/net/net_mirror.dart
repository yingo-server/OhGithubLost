/// L1 底座级 · 网络连接：镜像（加速）通道。
///
/// 原 App 依赖第三方加速域名访问 GitHub。这里把它抽象成**可插拔的通道列表**：
/// 通道按声明顺序尝试，全部不可用则回落直连（直连永远保留，是最后底线）。
library;

/// 镜像通道：把匹配的主机替换为加速主机。
class MirrorChannel {
  /// 创建通道。
  const MirrorChannel({
    required this.id,
    required this.pattern,
    required this.replacement,
    this.enabled = true,
  });

  /// 通道 ID（用于诊断与"本次已尝试"去重）。
  final String id;

  /// 匹配正则（作用于完整 URL）。
  final String pattern;

  /// 替换后的 URL 模板（支持 `$1` 等反向引用）。
  final String replacement;

  /// 是否启用（主题包 / 设置可关闭）。
  final bool enabled;

  /// 对 [url] 应用本通道；不匹配时返回 `null`。
  String? apply(String url) {
    if (!enabled) {
      return null;
    }
    final regex = RegExp(pattern);
    if (!regex.hasMatch(url)) {
      return null;
    }
    final mirrored = url.replaceFirstMapped(regex, (match) {
      var output = replacement;
      for (var index = 1; index <= match.groupCount; index++) {
        output = output.replaceAll('\$$index', match.group(index) ?? '');
      }
      return output;
    });
    return mirrored == url ? null : mirrored;
  }

  @override
  String toString() => 'MirrorChannel($id, enabled=$enabled)';
}

/// 镜像选择器：按声明顺序挑选下一个可用通道。
///
/// 刻意不做"测速择优"——那需要额外请求，且加速域名质量波动大；
/// 顺序 + 失败跳过（[skip]）在实践中更稳定，也更可预测。
class MirrorSelector {
  /// 创建选择器。
  MirrorSelector({List<MirrorChannel> channels = const <MirrorChannel>[]})
      : _channels = List<MirrorChannel>.of(channels);

  final List<MirrorChannel> _channels;

  /// 通道列表（只读）。
  List<MirrorChannel> get channels => List<MirrorChannel>.unmodifiable(_channels);

  /// 是否配置了可用通道。
  bool get isEmpty => _channels.every((channel) => !channel.enabled);

  /// 追加通道（诊断页手动添加加速源）。
  void add(MirrorChannel channel) => _channels.add(channel);

  /// 挑选下一个可用通道；无可用通道时返回 `null`（回落直连）。
  ({String id, String url})? mirrorFor(
    String url, {
    Set<String> skip = const <String>{},
  }) {
    for (final channel in _channels) {
      if (skip.contains(channel.id)) {
        continue;
      }
      final mirrored = channel.apply(url);
      if (mirrored != null) {
        return (id: channel.id, url: mirrored);
      }
    }
    return null;
  }

  /// 命中该 URL 的通道（不论是否已尝试）。
  MirrorChannel? channelFor(String url) {
    for (final channel in _channels) {
      if (channel.apply(url) != null) {
        return channel;
      }
    }
    return null;
  }
}

/// 内置通道：GitHub 常用加速（默认全部关闭，由设置 / 主题包启用）。
///
/// 之所以默认关闭：加速域名属于**第三方信任边界**，
/// 未经用户同意不应把仓库流量导向外部（见 `docs/BOOT.md` 信任策略）。
final List<MirrorChannel> defaultMirrorChannels = <MirrorChannel>[
  const MirrorChannel(
    id: 'ghproxy',
    pattern: r'^https://raw\.githubusercontent\.com/(.*)$',
    replacement: r'https://ghproxy.net/https://raw.githubusercontent.com/$1',
    enabled: false,
  ),
  const MirrorChannel(
    id: 'ghproxy-api',
    pattern: r'^https://api\.github\.com/(.*)$',
    replacement: r'https://ghproxy.net/https://api.github.com/$1',
    enabled: false,
  ),
];
