/// OGL 展示级 · 外链打开（唯一入口）。
///
/// ## 为什么要一个"唯一入口"
/// 详情页（仓库 README、议题正文与评论、PR、提交信息）都会遇到外链。
/// 若每页各写一遍，就会出现"有的页能开、有的页点了没反应"——
/// 而"点了没反应"正是最容易被当成"功能失效"的问题。
///
/// 因此这里只做一件事：**尽力打开，并如实返回结果**；
/// 失败时由调用方把 URL 摊开给用户（复制得出，不是干瞪眼）。
library;

import 'package:url_launcher/url_launcher.dart';

import '../app/error_surface.dart';

/// 用系统浏览器打开外链。
///
/// 返回 `true` = 已交给系统；`false` = 没打开（调用方必须**可见地**告诉用户）。
Future<bool> ogLOpenExternal(Uri url, {String tag = '链接'}) async {
  OgLAppLog.instance.add(tag, '打开外部链接：$url');
  try {
    if (url.scheme.isEmpty) {
      OgLAppLog.instance
          .add(tag, '链接缺少协议，拒绝打开：$url', severity: OgLNoticeSeverity.warning);
      return false;
    }
    final bool ok =
        await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      OgLAppLog.instance
          .add(tag, '系统没有可用的浏览器：$url', severity: OgLNoticeSeverity.warning);
    }
    return ok;
  } catch (error) {
    OgLAppLog.instance.add(
      tag,
      '打开链接失败：$error',
      severity: OgLNoticeSeverity.warning,
    );
    return false;
  }
}