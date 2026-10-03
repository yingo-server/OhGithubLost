/// L3 展示级 · 发布详情（说明 / 资产下载 / 编辑 / 删除）。
///
/// 补齐原"发布页只能看说明 + 删除"的缺口：
/// - **资产**：逐个列出（文件名 / 大小 / 下载次数），可**下载**
///   （交给内建下载器；Release 附件走内置代理加速，落盘到 `<ogl>/download/release/`）；
/// - **编辑**：标签 / 标题 / 说明 / 草稿 / 预发布，`PATCH` 后即时刷新；
/// - **删除**：二次确认；
/// - 返回时把"是否发生变更"带回列表页，列表据此刷新。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/error_surface.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/download_proxy.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/readme_view.dart';

/// 发布详情页。
class ReleaseDetailPage extends StatefulWidget {
  /// 创建页面。
  const ReleaseDetailPage({
    required this.surface,
    required this.fullName,
    required this.release,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 发布对象。
  final GhRelease release;

  @override
  State<ReleaseDetailPage> createState() => _ReleaseDetailPageState();
}

class _ReleaseDetailPageState extends State<ReleaseDetailPage> {
  late GhRelease _release = widget.release;
  bool _busy = false;

  Future<void> _edit() async {
    final TextEditingController tag =
        TextEditingController(text: _release.tagName);
    final TextEditingController name =
        TextEditingController(text: _release.name ?? '');
    final TextEditingController body =
        TextEditingController(text: _release.body ?? '');
    bool draft = _release.isDraft;
    bool prerelease = _release.isPrerelease;

    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setLocal) => AlertDialog(
          title: const Text('编辑发布'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: tag,
                  decoration: const InputDecoration(
                    labelText: '标签（tag）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: '说明（支持 Markdown）',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('草稿'),
                  value: draft,
                  onChanged: (bool v) => setLocal(() => draft = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('预发布'),
                  value: prerelease,
                  onChanged: (bool v) => setLocal(() => prerelease = v),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final String tagText = tag.text.trim();
    final String nameText = name.text.trim();
    final String bodyText = body.text;
    tag.dispose();
    name.dispose();
    body.dispose();
    if (submit != true || !mounted) {
      return;
    }
    if (tagText.isEmpty) {
      _toast('标签不能为空');
      return;
    }
    setState(() => _busy = true);
    try {
      final GhRelease updated = await widget.surface.domain.api.updateRelease(
        widget.fullName,
        _release.id,
        tagName: tagText,
        name: nameText,
        body: bodyText,
        draft: draft,
        prerelease: prerelease,
      );
      OgLAppLog.instance.result('发布', '已更新', updated.tagName);
      if (!mounted) {
        return;
      }
      setState(() {
        _release = updated;
      });
      _toast('已保存');
    } catch (error) {
      OgLAppLog.instance.add(
        '发布',
        '更新失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        _toast('保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除发布'),
        content: Text('将删除发布 ${_release.tagName}。该操作不易撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.deleteRelease(widget.fullName, _release.id);
      OgLAppLog.instance.result('发布', '已删除', _release.tagName);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        '发布',
        '删除失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        _toast('删除失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _download(GhAsset asset) async {
    final String? url = asset.downloadUrl;
    if (url == null || url.isEmpty) {
      _toast('该附件没有下载地址');
      return;
    }
    try {
      // 生效前缀：总开关关闭、或未同意协议时为 null（= 直连）。
      final String? accelBase =
          widget.surface.settings.settings.activeAccelPrefix;
      await widget.surface.domain.downloads.enqueue(
        url: ogLReleaseDownloadUrl(url, accelBase: accelBase),
        fileName: asset.name,
        category: IxDownloadCategory.release,
      );
      if (mounted) {
        _toast('已加入下载：${asset.name}');
      }
    } catch (error) {
      if (mounted) {
        _toast('加入下载失败：$error');
      }
    }
  }

  /// R5：附件详情（点击触发）。展示文件名 / 大小 / 类型 / 下载次数 / 直链，
  /// 并提供「下载」「复制链接」两个动作——**不再点一下就下载**。
  Future<void> _showAssetDetail(GhAsset asset) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                asset.name,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _assetKeyRow('大小', ghSizeText(asset.size)),
              _assetKeyRow('下载次数', '${asset.downloadCount}'),
              if (asset.contentType != null && asset.contentType!.isNotEmpty)
                _assetKeyRow('类型', asset.contentType!),
              if (asset.downloadUrl != null && asset.downloadUrl!.isNotEmpty)
                _assetKeyRow('直链', asset.downloadUrl!),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_download(asset));
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('下载'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_copyAssetLink(asset));
                      },
                      icon: const Icon(Icons.link),
                      label: const Text('复制链接'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// R5：长按附件的快捷操作（下载 / 复制链接 / 查看详情）。
  Future<void> _showAssetActions(GhAsset asset) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_download(asset));
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制下载链接'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_copyAssetLink(asset));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看文件详情'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_showAssetDetail(asset));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 复制附件的下载直链（**不**经加速通道，避免把通道地址暴露给用户）。
  Future<void> _copyAssetLink(GhAsset asset) async {
    final String? url = asset.downloadUrl;
    if (url == null || url.isEmpty) {
      _toast('该附件没有下载地址');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _toast('已复制下载链接');
  }

  Widget _assetKeyRow(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 72, child: Text(key)),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );

  Future<void> _copyNotes() async {
    final String text = _release.body ?? '';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _toast('已复制发布说明');
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> marks = <String>[
      if (_release.isDraft) '草稿',
      if (_release.isPrerelease) '预发布',
    ];
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _release.tagName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: _busy ? null : _edit,
            ),
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: '复制说明',
              onPressed: _copyNotes,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _busy ? null : _delete,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              _release.name == null || _release.name!.isEmpty
                  ? _release.tagName
                  : _release.name!,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              <String>[
                if (_release.publishedAt != null)
                  '发布 ${_release.publishedAt!.toIso8601String().split('T').first}',
                if (marks.isNotEmpty) marks.join(' / '),
                '${_release.assets.length} 个附件',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (_release.body != null && _release.body!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ReadmeView(
                    markdown: _release.body!,
                    onOpenLink: (Uri uri) {
                      unawaited(openExternalLink(uri, tag: '发布'));
                    },
                  ),
                ),
              ),
            ],
            const Divider(height: 32),
            Text('附件', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_release.assets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('这次发布没有附件'),
              )
            else
              for (final GhAsset asset in _release.assets)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(
                      asset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${ghSizeText(asset.size)} · ${asset.downloadCount} 次下载',
                    ),
                    trailing: const Icon(Icons.info_outline),
                    // R5：点击**先看详情**（不再直接触发下载）；长按弹出快捷操作。
                    onTap: () => unawaited(_showAssetDetail(asset)),
                    onLongPress: () => unawaited(_showAssetActions(asset)),
                  ),
                ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}