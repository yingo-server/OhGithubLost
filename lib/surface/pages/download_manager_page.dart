/// L3 展示级 · 下载管理（列表 + 进度 + 控制）。
///
/// - 逐条展示：文件名、分类、状态、大小 / 进度、速率；
/// - 控制：暂停 / 继续 / 取消 / 重试 / 移除 / 打开 / 复制路径；
/// - 数据来自中枢层的 [IxDownloadManager]（进度节流广播）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/ix/ix_download.dart';
import '../app/animations.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';

/// 下载管理页。
class DownloadManagerPage extends StatelessWidget {
  /// 创建页面。
  const DownloadManagerPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  IxDownloadManager get _manager => surface.domain.downloads;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: <Widget>[
          IconButton(
            tooltip: '清理已结束',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _manager.clearFinished,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _manager,
        builder: (BuildContext context, Widget? _) {
          final List<IxDownloadTask> tasks = _manager.tasks;
          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.download_outlined,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  const Text('还没有下载任务'),
                  const SizedBox(height: 4),
                  Text(
                    '在 Release 附件或仓库文件上点「下载」即可加入',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: tasks.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) => OgLReveal(
              delay: OgLAnim.stagger(context, index),
              child: _taskCard(context, theme, tasks[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _taskCard(BuildContext context, ThemeData theme, IxDownloadTask task) {
    final bool active = task.status == IxDownloadStatus.running;
    final bool paused = task.status == IxDownloadStatus.paused;
    final bool done = task.status == IxDownloadStatus.completed;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_iconFor(task.category), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  task.status.label,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: task.total > 0 ? task.progress : null,
              minHeight: 4,
            ),
            const SizedBox(height: 6),
            Text(
              _subtitleOf(task),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (task.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (active || task.status == IxDownloadStatus.queued)
                  IconButton(
                    tooltip: '暂停',
                    icon: const Icon(Icons.pause),
                    onPressed: () => unawaited(_manager.pause(task.id)),
                  ),
                if (paused)
                  IconButton(
                    tooltip: '继续',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => unawaited(_manager.resume(task.id)),
                  ),
                if (task.status == IxDownloadStatus.failed ||
                    task.status == IxDownloadStatus.canceled)
                  IconButton(
                    tooltip: '重试',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => unawaited(_manager.retry(task.id)),
                  ),
                if (active || task.status == IxDownloadStatus.queued || paused)
                  IconButton(
                    tooltip: '取消',
                    icon: const Icon(Icons.close),
                    onPressed: () => unawaited(_manager.cancel(task.id)),
                  ),
                if (done) ...<Widget>[
                  IconButton(
                    tooltip: '打开',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => unawaited(_openLocal(context, task)),
                  ),
                  IconButton(
                    tooltip: '复制路径',
                    icon: const Icon(Icons.content_copy),
                    onPressed: () => unawaited(_copyPath(context, task)),
                  ),
                ],
                IconButton(
                  tooltip: '移除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => unawaited(_manager.remove(task.id)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(IxDownloadCategory category) => switch (category) {
        IxDownloadCategory.release => Icons.new_releases_outlined,
        IxDownloadCategory.repo => Icons.folder_zip_outlined,
        IxDownloadCategory.gist => Icons.article_outlined,
        IxDownloadCategory.other => Icons.download_outlined,
      };

  static String _subtitleOf(IxDownloadTask task) {
    final String size = task.total > 0
        ? '${ghSizeText(task.received)} / ${ghSizeText(task.total)}'
        : ghSizeText(task.received);
    final String speed = task.status == IxDownloadStatus.running
        ? ' · ${ghSizeText(task.bytesPerSecond.round())}/s'
        : '';
    return '${task.category.label} · $size$speed';
  }

  Future<void> _openLocal(BuildContext context, IxDownloadTask task) async {
    try {
      final bool ok = await launchUrl(
        Uri.file(task.savePath),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        throw StateError('没有可处理该文件的应用');
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: task.savePath));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法直接打开，已复制文件路径')),
        );
      }
    }
  }

  Future<void> _copyPath(BuildContext context, IxDownloadTask task) async {
    await Clipboard.setData(ClipboardData(text: task.savePath));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制文件路径')),
      );
    }
  }
}