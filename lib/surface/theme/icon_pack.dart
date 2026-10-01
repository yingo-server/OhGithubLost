/// L3 展示级 · 主题体系：图标语义层（Icon Pack）。
///
/// ## 为什么不直接写 `Icons.xxx`
/// 界面里到处写 `Icons.settings` 会把"**语义**"和"**某个字体里的一个字形**"
/// 绑死。换一套图标包就得全文搜索替换，而且极容易漏。
///
/// 这里做一层映射：界面只认 [OgLIconName]（语义），
/// 由 [OgLIconSet] 决定用哪套字形。好处有三：
/// 1. 换图标包 = 换一个 id，**零处改动**；
/// 2. 语义名是 `enum`，新增语义时 `switch` 会**编译期强制**每套图标包补齐，
///    不可能出现"某套主题缺一个图标"；
/// 3. 图标包可以按风格挑选：极简线性（[OgLIconSets.minimalLine]）、
///    实心质感（[OgLIconSets.fontAwesomeSolid]）、原生（[OgLIconSets.materialOutlined]）。
library;

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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

/// 图标包契约。
abstract class OgLIconSet {
  /// 包 ID（进设置持久化）。
  String get id;

  /// 显示名。
  String get displayName;

  /// 解析语义到字形。
  IconData resolve(OgLIconName name);

  /// 该包是否使用实心字形（用于调整默认描边 / 视觉重量）。
  bool get isSolid;
}

/// 内置图标包。
abstract final class OgLIconSets {
  /// 全部内置包（顺序即设置页展示顺序）。
  static const List<OgLIconSet> all = <OgLIconSet>[
    materialOutlined,
    minimalLine,
    fontAwesomeSolid,
  ];

  /// 默认包：极简线性（最不抢戏，适合信息密集的代码工具）。
  static const OgLIconSet fallback = minimalLine;

  /// 按 ID 解析；未知 ID 回落到默认包（**绝不抛异常**——设置里的脏值不该让界面崩）。
  static OgLIconSet byId(String? id) {
    for (final set in all) {
      if (set.id == id) {
        return set;
      }
    }
    return fallback;
  }

  /// Material 线性（原生、克制）。
  static const OgLIconSet materialOutlined = _MaterialOutlinedIcons();

  /// 极简线性：Material Outlined 中笔画最细、留白最大的一组。
  static const OgLIconSet minimalLine = _MinimalLineIcons();

  /// Font Awesome 实心（质感、识别度高）。
  static const OgLIconSet fontAwesomeSolid = _FontAwesomeSolidIcons();
}

class _MaterialOutlinedIcons extends OgLIconSet {
  const _MaterialOutlinedIcons();

  @override
  String get id => 'material.outlined';

  @override
  String get displayName => 'Material 线性';

  @override
  bool get isSolid => false;

  @override
  IconData resolve(OgLIconName name) => switch (name) {
        OgLIconName.repository => Icons.folder_special_outlined,
        OgLIconName.folder => Icons.folder_outlined,
        OgLIconName.file => Icons.description_outlined,
        OgLIconName.branch => Icons.account_tree_outlined,
        OgLIconName.commit => Icons.commit_outlined,
        OgLIconName.compare => Icons.compare_arrows_outlined,
        OgLIconName.issue => Icons.report_problem_outlined,
        OgLIconName.pullRequest => Icons.merge_type_outlined,
        OgLIconName.release => Icons.local_offer_outlined,
        OgLIconName.tag => Icons.sell_outlined,
        OgLIconName.workflow => Icons.play_circle_outline,
        OgLIconName.search => Icons.search_outlined,
        OgLIconName.settings => Icons.settings_outlined,
        OgLIconName.sync => Icons.sync_outlined,
        OgLIconName.upload => Icons.upload_outlined,
        OgLIconName.download => Icons.download_outlined,
        OgLIconName.warning => Icons.warning_amber_outlined,
        OgLIconName.error => Icons.error_outline,
        OgLIconName.info => Icons.info_outline,
        OgLIconName.success => Icons.check_circle_outline,
        OgLIconName.conflict => Icons.call_split_outlined,
        OgLIconName.shield => Icons.shield_outlined,
        OgLIconName.key => Icons.vpn_key_outlined,
        OgLIconName.dns => Icons.dns_outlined,
        OgLIconName.mirror => Icons.swap_horiz_outlined,
        OgLIconName.mod => Icons.extension_outlined,
        OgLIconName.theme => Icons.palette_outlined,
        OgLIconName.layout => Icons.view_quilt_outlined,
        OgLIconName.terminal => Icons.terminal_outlined,
        OgLIconName.code => Icons.code_outlined,
        OgLIconName.star => Icons.star_outline,
        OgLIconName.fork => Icons.call_split_outlined,
        OgLIconName.history => Icons.history_outlined,
        OgLIconName.delete => Icons.delete_outline,
        OgLIconName.edit => Icons.edit_outlined,
        OgLIconName.add => Icons.add_outlined,
        OgLIconName.close => Icons.close_outlined,
        OgLIconName.chevronRight => Icons.chevron_right_outlined,
        OgLIconName.chevronDown => Icons.expand_more_outlined,
        OgLIconName.external => Icons.open_in_new_outlined,
        OgLIconName.filter => Icons.filter_list_outlined,
        OgLIconName.list => Icons.format_list_bulleted_outlined,
        OgLIconName.bug => Icons.bug_report_outlined,
        OgLIconName.book => Icons.menu_book_outlined,
        OgLIconName.clock => Icons.schedule_outlined,
      };
}

class _MinimalLineIcons extends OgLIconSet {
  const _MinimalLineIcons();

  @override
  String get id => 'minimal.line';

  @override
  String get displayName => '极简线性';

  @override
  bool get isSolid => false;

  @override
  IconData resolve(OgLIconName name) => switch (name) {
        OgLIconName.repository => Icons.folder_special,
        OgLIconName.folder => Icons.folder_open,
        OgLIconName.file => Icons.insert_drive_file_outlined,
        OgLIconName.branch => Icons.alt_route,
        OgLIconName.commit => Icons.commit,
        OgLIconName.compare => Icons.swap_calls,
        OgLIconName.issue => Icons.error_outline,
        OgLIconName.pullRequest => Icons.merge,
        OgLIconName.release => Icons.new_releases_outlined,
        OgLIconName.tag => Icons.label_outline,
        OgLIconName.workflow => Icons.bolt_outlined,
        OgLIconName.search => Icons.search,
        OgLIconName.settings => Icons.tune,
        OgLIconName.sync => Icons.refresh,
        OgLIconName.upload => Icons.arrow_upward,
        OgLIconName.download => Icons.arrow_downward,
        OgLIconName.warning => Icons.warning_amber_rounded,
        OgLIconName.error => Icons.priority_high_rounded,
        OgLIconName.info => Icons.info_outline_rounded,
        OgLIconName.success => Icons.check_rounded,
        OgLIconName.conflict => Icons.fork_right,
        OgLIconName.shield => Icons.verified_user_outlined,
        OgLIconName.key => Icons.password_outlined,
        OgLIconName.dns => Icons.public,
        OgLIconName.mirror => Icons.swap_horiz,
        OgLIconName.mod => Icons.widgets_outlined,
        OgLIconName.theme => Icons.contrast,
        OgLIconName.layout => Icons.view_agenda_outlined,
        OgLIconName.terminal => Icons.chevron_right,
        OgLIconName.code => Icons.data_object,
        OgLIconName.star => Icons.star_border_rounded,
        OgLIconName.fork => Icons.fork_right,
        OgLIconName.history => Icons.history_toggle_off,
        OgLIconName.delete => Icons.delete_outline_rounded,
        OgLIconName.edit => Icons.edit_note,
        OgLIconName.add => Icons.add,
        OgLIconName.close => Icons.close,
        OgLIconName.chevronRight => Icons.navigate_next,
        OgLIconName.chevronDown => Icons.keyboard_arrow_down,
        OgLIconName.external => Icons.north_east,
        OgLIconName.filter => Icons.filter_alt_outlined,
        OgLIconName.list => Icons.drag_handle,
        OgLIconName.bug => Icons.pest_control_outlined,
        OgLIconName.book => Icons.auto_stories_outlined,
        OgLIconName.clock => Icons.access_time,
      };
}

class _FontAwesomeSolidIcons extends OgLIconSet {
  const _FontAwesomeSolidIcons();

  @override
  String get id => 'fontawesome.solid';

  @override
  String get displayName => 'Font Awesome 实心';

  @override
  bool get isSolid => true;

  @override
  IconData resolve(OgLIconName name) => switch (name) {
        OgLIconName.repository => FontAwesomeIcons.bookBookmark,
        OgLIconName.folder => FontAwesomeIcons.folder,
        OgLIconName.file => FontAwesomeIcons.fileLines,
        OgLIconName.branch => FontAwesomeIcons.codeBranch,
        OgLIconName.commit => FontAwesomeIcons.codeCommit,
        OgLIconName.compare => FontAwesomeIcons.codeCompare,
        OgLIconName.issue => FontAwesomeIcons.circleExclamation,
        OgLIconName.pullRequest => FontAwesomeIcons.codePullRequest,
        OgLIconName.release => FontAwesomeIcons.boxOpen,
        OgLIconName.tag => FontAwesomeIcons.tag,
        OgLIconName.workflow => FontAwesomeIcons.bolt,
        OgLIconName.search => FontAwesomeIcons.magnifyingGlass,
        OgLIconName.settings => FontAwesomeIcons.gear,
        OgLIconName.sync => FontAwesomeIcons.arrowsRotate,
        OgLIconName.upload => FontAwesomeIcons.arrowUpFromBracket,
        OgLIconName.download => FontAwesomeIcons.download,
        OgLIconName.warning => FontAwesomeIcons.triangleExclamation,
        OgLIconName.error => FontAwesomeIcons.circleXmark,
        OgLIconName.info => FontAwesomeIcons.circleInfo,
        OgLIconName.success => FontAwesomeIcons.circleCheck,
        OgLIconName.conflict => FontAwesomeIcons.codeMerge,
        OgLIconName.shield => FontAwesomeIcons.shieldHalved,
        OgLIconName.key => FontAwesomeIcons.key,
        OgLIconName.dns => FontAwesomeIcons.globe,
        OgLIconName.mirror => FontAwesomeIcons.rightLeft,
        OgLIconName.mod => FontAwesomeIcons.puzzlePiece,
        OgLIconName.theme => FontAwesomeIcons.palette,
        OgLIconName.layout => FontAwesomeIcons.tableColumns,
        OgLIconName.terminal => FontAwesomeIcons.terminal,
        OgLIconName.code => FontAwesomeIcons.code,
        OgLIconName.star => FontAwesomeIcons.star,
        OgLIconName.fork => FontAwesomeIcons.codeFork,
        OgLIconName.history => FontAwesomeIcons.clockRotateLeft,
        OgLIconName.delete => FontAwesomeIcons.trashCan,
        OgLIconName.edit => FontAwesomeIcons.penToSquare,
        OgLIconName.add => FontAwesomeIcons.plus,
        OgLIconName.close => FontAwesomeIcons.xmark,
        OgLIconName.chevronRight => FontAwesomeIcons.chevronRight,
        OgLIconName.chevronDown => FontAwesomeIcons.chevronDown,
        OgLIconName.external => FontAwesomeIcons.arrowUpRightFromSquare,
        OgLIconName.filter => FontAwesomeIcons.filter,
        OgLIconName.list => FontAwesomeIcons.list,
        OgLIconName.bug => FontAwesomeIcons.bug,
        OgLIconName.book => FontAwesomeIcons.book,
        OgLIconName.clock => FontAwesomeIcons.clock,
      };
}