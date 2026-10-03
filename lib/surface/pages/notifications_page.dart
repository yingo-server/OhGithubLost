/// L3 展示级 · 通知中心（运行事件与错误）。
///
/// 汇总应用运行期的事件：成功结果、告警与错误。
/// 数据来自 [OgLAppLog]（同时落盘），可复制单条用于反馈。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/error_surface.dart';

/// 通知中心页。
class NotificationsPage extends StatefulWidget {
  /// 创建页面。
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  /// 过滤：0 全部 / 1 告警 / 2 错误。
  int _filter = 0;

  static String _fmt(DateTime time) {
    final DateTime t = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  bool _match(OgLAppLogEntry entry) {
    switch (_filter) {
      case 1:
        return entry.severity == OgLNoticeSeverity.warning ||
            entry.severity == OgLNoticeSeverity.critical;
      case 2:
        return entry.severity == OgLNoticeSeverity.critical;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('通知中心')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text('全部')),
                ButtonSegment<int>(value: 1, label: Text('告警')),
                ButtonSegment<int>(value: 2, label: Text('错误')),
              ],
              selected: <int>{_filter},
              showSelectedIcon: false,
              onSelectionChanged: (Set<int> selection) {
                if (selection.isNotEmpty) {
                  setState(() => _filter = selection.first);
                }
              },
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: OgLAppLog.instance,
              builder: (BuildContext context, Widget? _) {
                final List<OgLAppLogEntry> entries =
                    OgLAppLog.instance.entries.where(_match).toList();
                if (entries.isEmpty) {
                  return Center(
                    child: Text('没有符合条件的事件', style: theme.textTheme.bodySmall),
                  );
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final OgLAppLogEntry entry = entries[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        _iconOf(entry.severity),
                        color: _colorOf(theme, entry.severity),
                        size: 20,
                      ),
                      title: Text(
                        entry.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${entry.area} · ${_fmt(entry.at)}'),
                      trailing: IconButton(
                        tooltip: '复制',
                        icon: const Icon(Icons.content_copy, size: 18),
                        onPressed: () {
                          unawaited(Clipboard.setData(
                            ClipboardData(text: entry.toDisplay()),
                          ));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制该条事件')),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconOf(OgLNoticeSeverity severity) => switch (severity) {
        OgLNoticeSeverity.critical => Icons.error_outline,
        OgLNoticeSeverity.warning => Icons.warning_amber_rounded,
        OgLNoticeSeverity.info => Icons.check_circle_outline,
      };

  static Color _colorOf(ThemeData theme, OgLNoticeSeverity severity) =>
      switch (severity) {
        OgLNoticeSeverity.critical => theme.colorScheme.error,
        OgLNoticeSeverity.warning => theme.colorScheme.tertiary,
        OgLNoticeSeverity.info => theme.colorScheme.primary,
      };
}