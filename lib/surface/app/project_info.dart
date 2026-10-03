/// L3 展示级 · 项目元数据（名称 / 主要开发者 / 仓库坐标 / 许可）。
///
/// ## 为什么单独成文件
/// 关于页、捐赠 star、开源许可三处都要用到同一组事实（项目名、仓库坐标、许可）。
/// 把事实收敛到一处，避免三份副本各自漂移。
///
/// ## 分层
/// 本文件属 `surface`（L3）的**纯常量**：不依赖任何运行时对象，
/// 也不引用 `base` / `domain`，可被页面与装配层安全共享。
library;

/// 项目元数据。
abstract final class OgLProjectInfo {
  /// 项目名称。
  static const String name = 'OhGithubLost';

  /// 简称。
  static const String abbreviation = 'OGL';

  /// 主要开发者。
  static const String mainDeveloper = 'yingo-server';

  /// 仓库所属账号。
  static const String repoOwner = 'yingo-server';

  /// 仓库名称。
  static const String repoName = 'OhGithubLost';

  /// 仓库全名（`owner/name`）。
  static const String repoFullName = '$repoOwner/$repoName';

  /// 仓库地址。
  static const String repositoryUrl = 'https://github.com/$repoFullName';

  /// 议题地址。
  static const String issuesUrl = '$repositoryUrl/issues';

  /// 本项目许可标识。
  static const String licenseId = 'AGPL-3.0';

  /// 本项目许可名称。
  static const String licenseName = 'GNU Affero General Public License v3.0';

  /// 本项目许可地址。
  static const String licenseUrl =
      'https://www.gnu.org/licenses/agpl-3.0.html';
}

/// 第三方依赖与其许可（开源许可栏目展示用）。
///
/// 只列**运行期真正被 import 的包**（见 `pubspec.yaml` 的依赖说明）；
/// 开发期依赖（`flutter_lints` 等）不进入发布产物，因此不在此列。
class OgLDependencyLicense {
  /// 创建条目。
  const OgLDependencyLicense(this.name, this.license, this.purpose);

  /// 包名。
  final String name;

  /// 许可标识。
  final String license;

  /// 在本项目里的用途。
  final String purpose;
}

/// 第三方依赖清单（顺序与 `pubspec.yaml` 保持一致）。
const List<OgLDependencyLicense> kOgLDependencyLicenses =
    <OgLDependencyLicense>[
  OgLDependencyLicense('path_provider', 'BSD-3-Clause', '跨平台目录规划'),
  OgLDependencyLicense('flutter_secure_storage', 'MIT', '令牌安全存储'),
  OgLDependencyLicense('crypto', 'BSD-3-Clause', '摘要计算'),
  OgLDependencyLicense('cryptography', 'Apache-2.0', '引导清单签名校验'),
  OgLDependencyLicense('flutter_markdown', 'BSD-3-Clause', 'Markdown 渲染'),
  OgLDependencyLicense('url_launcher', 'BSD-3-Clause', '外链打开'),
  OgLDependencyLicense('re_editor', 'MIT', '代码编辑器内核（行号 / 查找替换 / 撤销重做 / 折叠）'),
  OgLDependencyLicense('re_highlight', 'MIT', '语法高亮（highlight.js 的 Dart 移植）'),
  OgLDependencyLicense('permission_handler', 'MIT', '运行时权限请求与系统设置入口'),
  OgLDependencyLicense('background_downloader', 'MIT', '多平台后台下载（断点续传 / 队列）'),
  OgLDependencyLicense('archive', 'MIT', 'Actions 日志 zip 解压'),
  OgLDependencyLicense('flutter_localizations', 'BSD-3-Clause', '系统组件本地化'),
];