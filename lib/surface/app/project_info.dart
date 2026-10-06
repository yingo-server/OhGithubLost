

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

import '../i18n/og_l_i18n.dart';

/// 取 `shell` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('shell', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

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
  static const String licenseId = 'Apache-2.0';

  /// 本项目许可名称。
  static const String licenseName = 'Apache License 2.0';

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
final List<OgLDependencyLicense> kOgLDependencyLicenses =
    <OgLDependencyLicense>[
  OgLDependencyLicense('path_provider', 'BSD-3-Clause', _t('featureCrossPlatformDirs')),
  OgLDependencyLicense('flutter_secure_storage', 'MIT', _t('featureTokenVault')),
  OgLDependencyLicense('crypto', 'BSD-3-Clause', _t('featureDigest')),
  OgLDependencyLicense('cryptography', 'Apache-2.0', _t('featureManifestSignature')),
  OgLDependencyLicense('flutter_markdown', 'BSD-3-Clause', _t('featureMarkdown')),
  OgLDependencyLicense('url_launcher', 'BSD-3-Clause', _t('featureExternalLink')),
  OgLDependencyLicense('re_editor', 'MIT', _t('featureCodeEditor')),
  OgLDependencyLicense('re_highlight', 'MIT', _t('featureHighlight')),
  OgLDependencyLicense('permission_handler', 'MIT', _t('featurePermissions')),
  OgLDependencyLicense('background_downloader', 'MIT', _t('featureDownloads')),
  OgLDependencyLicense('archive', 'MIT', _t('featureActionsZip')),
  OgLDependencyLicense('flutter_localizations', 'BSD-3-Clause', _t('featureLocalization')),
];