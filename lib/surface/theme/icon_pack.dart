/// L3 展示级 · 主题体系：图标语义层（Icon Pack）。
///
/// ## 为什么不直接写 `Icons.xxx`
/// 界面里到处写 `Icons.settings` 会把"**语义**"和"**某个字体里的一个字形**"
/// 绑死：换一套图标就得全文搜索替换，而且极容易漏。这里保留一层映射 ——
/// 界面只认 [OgLIconName]（语义），由 [OgLIconSet] 决定**风格**。
///
/// ## 现在（W3 起）：全部自绘矢量
/// 几何形状来自 `lib/surface/icons/og_l_vector_icon.dart`（手写 `d` 路径，
/// 24 × 24 网格）；图标包只回答两件事：**风格**（细线 / 标准 / 实心）与
/// **线宽**。于是：
/// 1. 界面上**不可能**再出现 Material 字形（渲染入口只有 `OgLIcon`）；
/// 2. 换风格 = 换一个 id，零处改动；
/// 3. 零字体、零外部资源（不打包 ttf，也就不存在"字体缺字形"这类事故）。
///
/// ## 关于 Font Awesome（重要教训，留档）
/// 最初这里用的第三套包是 `font_awesome_flutter`，**它在 Flutter 3.47 上无法编译**：
/// 该包整体建立在 `extends IconData` 之上，而新版 Flutter 把 `IconData` 收成了
/// `final class`（换版本也救不了，历代版本都 extends）。既然我们要的是
/// "自己的尖锐图标"，**自绘矢量**是唯一同时满足"零外部资源 + 完全可控"的路。
library;

/// 图标风格。
enum OgLIconStyle {
  /// 细线（极简；信息密集场景）。
  line,

  /// 标准线宽（默认）。
  bold,

  /// 实心（闭合形状填充 + 加粗描边；识别度最高）。
  solid,
}

/// 图标语义（界面唯一允许引用的"名字"）。
enum OgLIconName {
  /// 仓库 / 项目。
  repository,

  /// 文件夹。
  folder,

  /// 文件。
  file,

  /// 分支。
  branch,

  /// 提交。
  commit,

  /// 合并 / 对比。
  compare,

  /// Issue。
  issue,

  /// Pull Request。
  pullRequest,

  /// 发布 / 版本。
  release,

  /// 标签。
  tag,

  /// 工作流 / 动作。
  workflow,

  /// 搜索。
  search,

  /// 设置。
  settings,

  /// 同步 / 刷新。
  sync,

  /// 上传。
  upload,

  /// 下载。
  download,

  /// 警告。
  warning,

  /// 错误。
  error,

  /// 信息。
  info,

  /// 成功。
  success,

  /// 冲突 / 分歧。
  conflict,

  /// 安全 / 权限。
  shield,

  /// 密钥 / 令牌。
  key,

  /// DNS / 网络。
  dns,

  /// 加速通道 / 镜像。
  mirror,

  /// Mod 扩展。
  mod,

  /// 主题 / 外观。
  theme,

  /// 布局。
  layout,

  /// 终端。
  terminal,

  /// 代码。
  code,

  /// 星标。
  star,

  /// 复刻。
  fork,

  /// 历史。
  history,

  /// 删除。
  delete,

  /// 编辑。
  edit,

  /// 新增。
  add,

  /// 关闭。
  close,

  /// 左箭头（返回）。
  arrowLeft,

  /// 评论 / 讨论。
  chat,

  /// 右箭头（进入）。
  chevronRight,

  /// 下箭头（展开）。
  chevronDown,

  /// 外部链接。
  external,

  /// 筛选。
  filter,

  /// 列表。
  list,

  /// 调试 / 诊断。
  bug,

  /// 指南 / 手册。
  book,

  /// 时间。
  clock,
}

/// 图标包契约（只描述风格；几何形状是共享的自绘矢量）。
abstract class OgLIconSet {
  /// 常量构造（三套内置包都是 `const` 单例）。
  const OgLIconSet();

  /// 包 ID（进设置持久化；**历史 ID 保持不变**，否则老设置会失去选择）。
  String get id;

  /// 显示名。
  String get displayName;

  /// 风格。
  OgLIconStyle get style;

  /// 线宽（24 设计网格下的基准值）。
  double get strokeWidth;
}

/// 内置图标包。
abstract final class OgLIconSets {
  /// 全部内置包（顺序即设置页展示顺序）。
  static const List<OgLIconSet> all = <OgLIconSet>[
    materialOutlined,
    minimalLine,
    materialFilled,
  ];

  /// 默认包：标准线性（最不抢戏，适合信息密集的代码工具）。
  static const OgLIconSet fallback = materialOutlined;

  /// 按 ID 解析；未知 ID 回落到默认包（**绝不抛异常**——设置里的脏值不该让界面崩）。
  static OgLIconSet byId(String? id) {
    for (final OgLIconSet set in all) {
      if (set.id == id) {
        return set;
      }
    }
    return fallback;
  }

  /// 标准线性（Primer 语感）。
  static const OgLIconSet materialOutlined = _Pack(
    id: 'material.outlined',
    displayName: '标准线性',
    style: OgLIconStyle.bold,
    strokeWidth: 1.75,
  );

  /// 极简细线。
  static const OgLIconSet minimalLine = _Pack(
    id: 'minimal.line',
    displayName: '极简细线',
    style: OgLIconStyle.line,
    strokeWidth: 1.35,
  );

  /// 锐利实心（闭合形状填充）。
  static const OgLIconSet materialFilled = _Pack(
    id: 'material.filled',
    displayName: '锐利实心',
    style: OgLIconStyle.solid,
    strokeWidth: 1.7,
  );
}

class _Pack extends OgLIconSet {
  const _Pack({
    required this.id,
    required this.displayName,
    required this.style,
    required this.strokeWidth,
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  final OgLIconStyle style;

  @override
  final double strokeWidth;
}