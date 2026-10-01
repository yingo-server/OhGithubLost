/// 发布信任根（Release Trust Root）：内嵌 Ed25519 公钥。
///
/// 信任模型（见 `docs/BOOT.md` §2）：
/// - CI 构建时用对应**私钥**给引导清单（Boot Manifest）签名；
/// - 应用启动时用这里的**公钥**校验签名；签名不符 → 拒绝启动；
/// - 私钥存于 `.github/signing/ogl-boot-ed25519.key`（个人分发场景，随仓库保管）；
/// - 公钥/私钥**轮换**会让旧版本无法验证新清单：必须按"先升公钥、后换签名"
///   的次序走版本过渡，禁止直接替换。
///
/// 防脱节：`test/kernel/boot_release_chain_test.dart` 在 CI 中验证
/// 「仓库私钥能签出本公钥可验的清单」，任何一边被改动都会红。
library;

/// 32 字节 Ed25519 公钥原始字节。
///
/// base64：`3sPk7i1MNSkRE1VCzgpli7e/zWJxrnPWazVS7cfGcjc=`
const List<int> kOgLReleasePublicKey = <int>[
  222, 195, 228, 238, 45, 76, 53, 41, 17, 19, 85, 66, 206, 10, 101, 139,
  183, 191, 205, 98, 113, 174, 115, 214, 107, 53, 82, 237, 199, 198, 114, 55,
];

/// 公钥的 base64 形式（日志与文档展示用）。
const String kOgLReleasePublicKeyBase64 =
    '3sPk7i1MNSkRE1VCzgpli7e/zWJxrnPWazVS7cfGcjc=';