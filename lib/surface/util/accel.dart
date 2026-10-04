/// L3 展示级 · Release 下载加速通道（模型 / 内置通道 / 法律声明）。
///
/// ## 能力
/// - **一个总开关**：`releaseProxyEnabled`——关掉即全部走直连；
/// - **多个通道**：内置通道（开发者自建，唯一）+ 任意多个用户自定义通道；
/// - **选择一个**：`releaseProxySelectedId` 指定当前生效通道。
///
/// ## 法律声明（必须显式同意后才可启用）
/// 通道会把"下载请求"导向应用之外的服务器，涉及第三方信任边界，因此：
/// - 自定义（第三方）通道 → **外来服务自负责任协议**；
/// - 内置通道 → **内置通道安全声明**。
/// 两个协议的**文本与版本号**都收敛在本文件；用户同意后会记录
/// 版本号与时间（[kOgLAccelConsentVersion]），文本升版必须重新同意。
library;

import '../i18n/og_l_i18n.dart';

/// 取 `common` 分片文案。
String _t(String key) => OgLI18n.instance.t('common', key);

/// 同意协议的版本号：**文本任何实质修改都必须 +1**，以便重新征求同意。
const int kOgLAccelConsentVersion = 1;

/// 一个下载加速通道。
class OgLAccelChannel {
  /// 创建通道。
  const OgLAccelChannel({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.builtin = false,
  });

  /// 唯一标识（自定义通道由用户创建，内置固定为 [kOgLAccelBuiltinId]）。
  final String id;

  /// 展示名。
  final String name;

  /// 前缀地址（形如 `https://host:port/`，以 `/` 结尾）。
  final String baseUrl;

  /// 是否内置（内置不可删除）。
  final bool builtin;

  /// 由 JSON 构造（容错）。
  static OgLAccelChannel? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? id = raw['id'];
    final Object? name = raw['name'];
    final Object? base = raw['baseUrl'];
    if (id is! String || id.isEmpty || base is! String || base.isEmpty) {
      return null;
    }
    return OgLAccelChannel(
      id: id,
      name: name is String && name.isNotEmpty ? name : id,
      baseUrl: base,
    );
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
      };

  @override
  bool operator ==(Object other) =>
      other is OgLAccelChannel && other.id == id && other.baseUrl == baseUrl;

  @override
  int get hashCode => Object.hash(id, baseUrl);
}

/// 内置通道 id。
const String kOgLAccelBuiltinId = 'builtin';

/// 内置通道前缀（开发者自建，HTTPS）。
const String kOgLAccelBuiltinBaseUrl = 'https://server.344977.xyz:9999/';

/// 内置通道。
const OgLAccelChannel kOgLAccelBuiltinChannel = OgLAccelChannel(
  id: kOgLAccelBuiltinId,
  name: _t('accelBuiltin'),
  baseUrl: kOgLAccelBuiltinBaseUrl,
  builtin: true,
);

/// 校验自定义通道地址（返回 `null` = 通过）。
String? ogLValidateAccelBaseUrl(String raw) {
  final String input = raw.trim();
  if (input.isEmpty) {
    return _t('accelUrlRequired');
  }
  if (RegExp(r'[\u2E80-\u9FFF\uFF00-\uFFEF]').hasMatch(input)) {
    return _t('accelUrlCjk');
  }
  if (!input.startsWith('https://') && !input.startsWith('http://')) {
    return _t('accelUrlScheme');
  }
  if (input.contains(' ')) {
    return _t('accelUrlSpace');
  }
  if (input.startsWith('http://')) {
    // 明文会被 Android 9+ 直接拦截（此前 4.4.0 的故障根因），提前告知。
    return _t('accelUrlPlainHttp');
  }
  if (!input.endsWith('/')) {
    return _t('accelUrlTrailingSlash');
  }
  return null;
}

/// 归一化：确保以 `/` 结尾（便于拼接原始 URL）。
String ogLNormalizeAccelBase(String raw) {
  final String trimmed = raw.trim();
  return trimmed.endsWith('/') ? trimmed : '$trimmed/';
}

/// 外来服务（第三方 / 自定义通道）自负责任协议。
const String kOgLThirdPartyAccelDisclaimer = '''
外来服务自负责任协议

1. 你即将启用的是一个由**第三方**（并非本应用开发者）提供的下载加速服务。
   该服务由你自行添加，其运营主体、可用性、带宽、稳定性、内容完整性与安全性
   均由该第三方负责，本应用不对其作出任何形式的担保。

2. 一旦启用，你的 Release 附件下载请求（包含目标下载地址）将被发送至该
   第三方服务器。请你自行确认你信任该服务提供者，并自行评估由此带来的
   隐私、数据与合规风险。

3. 本应用不对因使用该第三方服务而产生的下载失败、数据损坏、内容被篡改、
   隐私泄露、额外费用或任何直接/间接损失承担责任。

4. 你应自行核查并遵守你所在国家/地区、所在组织关于网络访问与数据传输的
   法律法规与内部政策。

5. 你可以随时关闭总开关或移除该通道以终止使用。关闭后 Release 附件将
   恢复直连下载。

6. 勾选同意即表示你已完整阅读、理解并自愿接受上述全部内容。
''';

/// 内置通道安全声明。
const String kOgLBuiltinAccelSecurityStatement = '''
内置通道安全声明

1. 内置通道由**本应用开发者自行部署与维护**，仅用于加速 GitHub Release
   附件的下载，不提供任何其它用途。

2. **不接收账号凭据**：使用内置通道时，请求中不包含你的 GitHub 访问令牌
   （Token）；通道不参与你的登录、不读取你的仓库数据。

3. **传输加密**：内置通道使用 HTTPS（TLS）加密传输。为完成加速，目标附件的
   下载地址会被该通道知晓；通道不长期保存你所下载文件的副本。

4. **可用性**：通道可能因维护、限流、网络故障或不可抗力而中断。中断时
   Release 附件仍可通过**直连**下载，功能不受影响。

5. **不构成绝对承诺**：本声明是对通道技术特性的如实说明，不构成对
   "绝对可用"或"绝对安全"的承诺。若你对此有顾虑，请使用直连，或添加
   你信任的自定义通道。

6. 你可以在任何时候关闭总开关以停止使用该通道；本声明自你勾选同意之日起
   对你的使用行为生效。
''';

/// 按通道类型返回对应协议文本（走 i18n；中文源文见上方常量）。
String ogLAccelAgreementFor(OgLAccelChannel channel) =>
    channel.builtin ? _t('accelBuiltinStatement') : _t('accelThirdPartyDisclaimer');

/// 通道展示名（内置通道走 i18n，自定义通道用用户填写的名字）。
String ogLAccelChannelName(OgLAccelChannel channel) =>
    channel.builtin ? _t('accelBuiltin') : channel.name;