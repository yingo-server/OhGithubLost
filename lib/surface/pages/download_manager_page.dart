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

import '../app/animations.dart';

import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';

import '../types.dart';
import '../util/gh_format.dart';

/// 取 `download_manager_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('download_manager_page', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 下载管理页。
class DownloadManagerPage extends StatelessWidget {
  /// 创建页面。
  const DownloadManagerPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;


  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title:  Text(_t('title')),
        actions: <Widget>[
          IconButton(
            tooltip: _t('clearFinished'),
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: surface.clearFinishedDownloads,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: surface.downloadsListenable,
        builder: (BuildContext context, Widget? _) {
          final List<IxDownloadTask> tasks = surface.downloadTasks;
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
                   Text(_t('empty')),
                  const SizedBox(height: 4),
                  Text(
                    _t('emptyHint'),
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
                    tooltip: _t('pause'),
                    icon: const Icon(Icons.pause),
                    onPressed: () => unawaited(surface.pauseDownload(task.id)),
                  ),
                if (paused)
                  IconButton(
                    tooltip: _t('resume'),
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => unawaited(surface.resumeDownload(task.id)),
                  ),
                if (task.status == IxDownloadStatus.failed ||
                    task.status == IxDownloadStatus.canceled)
                  IconButton(
                    tooltip: _t('retry'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () => unawaited(surface.retryDownload(task.id)),
                  ),
                if (active || task.status == IxDownloadStatus.queued || paused)
                  IconButton(
                    tooltip: _t('cancel'),
                    icon: const Icon(Icons.close),
                    onPressed: () => unawaited(surface.cancelDownload(task.id)),
                  ),
                if (done) ...<Widget>[
                  IconButton(
                    tooltip: _t('open'),
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => unawaited(_openLocal(context, task)),
                  ),
                  IconButton(
                    tooltip: _t('copyPath'),
                    icon: const Icon(Icons.content_copy),
                    onPressed: () => unawaited(_copyPath(context, task)),
                  ),
                ],
                IconButton(
                  tooltip: _t('remove'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => unawaited(surface.removeDownload(task.id)),
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
        throw StateError(_t('noAppForFile'));
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: task.savePath));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_t('cannotOpenCopied'))),
        );
      }
    }
  }

  Future<void> _copyPath(BuildContext context, IxDownloadTask task) async {
    await Clipboard.setData(ClipboardData(text: task.savePath));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('pathCopied'))),
      );
    }
  }
}