/// L3 展示级 · **自绘矢量图标**（W3 交付）。
///
/// ## 为什么自绘
/// 之前所有图标都来自 Material 字形 —— 那是别人的设计语言，和我们
/// "发丝描边 + 直角偏锐" 的 Primer 语言并不一致；而且字体字形无法做
/// "更概念、更尖锐" 的取舍。这里改为**手写矢量**：
///
/// - **零外部资源**：没有 ttf、没有图片，几何图形直接写在代码里；
/// - **更概念 / 更尖锐**：全部由直线构成（圆一律用八边形/菱形代替），
///   端点 `butt`、拐角 `miter` —— 不出现任何圆头圆角；
/// - **网格统一**：所有形状画在 24 × 24 设计网格内，渲染时等比缩放，
///   因此 16 / 20 / 24 / 32 都清晰。
///
/// ## 数据格式
/// 每个图标是一段 `d` 字符串，只允许四种命令：
/// `M x y`（移动到）/ `L x y`（连线到）/ `H x`（水平连线）/ `V y`（垂直连线）
/// 与 `Z`（闭合）。**不允许曲线**（这是"尖锐"的技术保证）。
library;

import 'dart:ui';

import '../theme/icon_pack.dart';

/// 自绘矢量图标数据（24 × 24 设计网格）。
abstract final class OgLVectorIconData {
  /// 语义名 → `d` 字符串。
  ///
  /// 约定：只使用 M / L / H / V / Z，且坐标落在 `[0, 24]`。
  static const Map<OgLIconName, String> paths = <OgLIconName, String>{
    // ── 仓库与文件 ────────────────────────────────────────────────
    OgLIconName.repository: 'M3 4 H21 V20 H3 Z M3 9 H21',
    OgLIconName.folder: 'M3 6 H10 L12 9 H21 V19 H3 Z',
    OgLIconName.file: 'M6 3 H14 L19 8 V21 H6 Z M14 3 V8 H19',
    // ── 版本控制 ──────────────────────────────────────────────────
    OgLIconName.branch:
        'M7 4 V20 M7 12 H16 V6 M5.5 2.5 H8.5 V5.5 H5.5 Z M14.5 4.5 H17.5 V7.5 H14.5 Z',
    OgLIconName.commit: 'M12 4 V9 M12 15 V20 M9 9 H15 V15 H9 Z',
    OgLIconName.compare:
        'M4 7 H16 M13 4 L16 7 L13 10 M20 17 H8 M11 14 L8 17 L11 20',
    OgLIconName.issue:
        'M12 3 L21 12 L12 21 L3 12 Z M11 8 H13 V14 H11 Z M11.5 16 H12.5 V17 H11.5 Z',
    OgLIconName.pullRequest:
        'M7 4 V20 M17 8 V20 M7 9 H13 M13 6 L16 9 L13 12',
    OgLIconName.release: 'M4 4 H12 L20 12 L12 20 L4 12 Z M8 8 H9 V9 H8 Z',
    OgLIconName.tag: 'M4 4 H11 L20 13 L13 20 L4 11 Z M8 8 H9 V9 H8 Z',
    OgLIconName.fork:
        'M7 4 V19 M7 12 H16 V5 M5.5 2.5 H8.5 V5.5 H5.5 Z M14.5 3.5 H17.5 V6.5 H14.5 Z M14.5 16.5 H17.5 V19.5 H14.5 Z',
    OgLIconName.history: 'M5 4 V20 M9 8 H20 M9 13 H18 M9 18 H15',
    OgLIconName.workflow: 'M5 4 H19 V20 H5 Z M9 10 H15 M9 14 H13',
    // ── 操作 ──────────────────────────────────────────────────────
    OgLIconName.search: 'M9.5 4 H14.5 L19 8.5 V13.5 L14.5 18 H9.5 L5 13.5 V8.5 Z M15.5 15.5 L21 21',
    OgLIconName.settings:
        'M10 3 H14 L15 6 L18 7 L21 5 L22 9 L19 11 V13 L22 15 L21 19 L18 17 L15 18 L14 21 H10 L9 18 L6 17 L3 19 L2 15 L5 13 V11 L2 9 L3 5 L6 7 L9 6 Z M11 10 H13 V14 H11 Z',
    OgLIconName.sync: 'M4 9 L9 4 L14 9 M4 9 H16 M20 15 L15 20 L10 15 M20 15 H8',
    OgLIconName.upload: 'M12 4 V20 M6 10 L12 4 L18 10',
    OgLIconName.download: 'M12 4 V20 M6 14 L12 20 L18 14',
    OgLIconName.delete:
        'M5 7 H19 M9 7 V4 H15 V7 M7 7 V20 H17 V7 M10 11 V17 M14 11 V17',
    OgLIconName.edit: 'M4 20 L5 15 L16 4 L20 8 L9 19 Z M14 6 L18 10',
    OgLIconName.add: 'M12 4 V20 M4 12 H20',
    OgLIconName.close: 'M5 5 L19 19 M19 5 L5 19',
    OgLIconName.arrowLeft: 'M3 12 H21 M10 5 L3 12 L10 19',
    OgLIconName.chat: 'M3 4 H21 V17 H13 L8 21 V17 H3 Z M6 8 H18 M6 12 H15',
    OgLIconName.chevronRight: 'M9 5 L16 12 L9 19',
    OgLIconName.chevronDown: 'M5 9 L12 16 L19 9',
    OgLIconName.external: 'M14 4 H20 V10 M20 4 L11 13 M18 14 V20 H4 V6 H10',
    OgLIconName.filter: 'M3 5 H21 L14 13 V20 L10 17 V13 Z',
    OgLIconName.list: 'M4 6 H20 M4 12 H20 M4 18 H14',
    // ── 状态与安全 ────────────────────────────────────────────────
    OgLIconName.warning:
        'M12 3 L22 20 H2 Z M11 9 H13 V15 H11 Z M11.5 17 H12.5 V18 H11.5 Z',
    OgLIconName.error: 'M12 3 L21 12 L12 21 L3 12 Z M8 8 L16 16 M16 8 L8 16',
    OgLIconName.info:
        'M9 4 H15 L20 9 V15 L15 20 H9 L4 15 V9 Z M11 7 H13 V9 H11 Z M11 11 H13 V16 H11 Z',
    OgLIconName.success: 'M4 13 L9 18 L20 6',
    OgLIconName.conflict:
        'M6 4 V20 M6 10 H12 M12 6 L15 10 L12 14 M13 12 H20 M17 9 V15',
    OgLIconName.shield: 'M12 3 L20 6 V12 L12 21 L4 12 V6 Z',
    OgLIconName.key: 'M15 4 L20 9 L15 14 L13 12 L8 17 L4 13 L9 8 L7 6 Z M17 7 H18 V8 H17 Z',
    OgLIconName.dns: 'M4 5 H20 V10 H4 Z M4 14 H20 V19 H4 Z M7 7 H8 V8 H7 Z M7 16 H8 V17 H7 Z',
    OgLIconName.mirror: 'M3 8 H15 M12 5 L15 8 L12 11 M21 16 H9 M12 13 L9 16 L12 19',
    OgLIconName.mod: 'M4 4 H10 V10 H4 Z M14 4 H20 V10 H14 Z M4 14 H10 V20 H4 Z M17 13 V21 M13 17 H21',
    OgLIconName.theme: 'M12 3 L21 12 L12 21 L3 12 Z M12 3 V21',
    OgLIconName.layout: 'M3 4 H21 V20 H3 Z M10 4 V20 M10 12 H21',
    OgLIconName.terminal: 'M4 4 H20 V20 H4 Z M7 9 L10 12 L7 15 M12 15 H17',
    OgLIconName.code: 'M9 6 L4 12 L9 18 M15 6 L20 12 L15 18',
    OgLIconName.star:
        'M12 3 L14.5 9 L21 9.5 L16 13.6 L17.6 20 L12 16.2 L6.4 20 L8 13.6 L3 9.5 L9.5 9 Z',
    OgLIconName.bug:
        'M9 4 L12 7 L15 4 M8 8 H16 V16 H8 Z M8 12 H4 M20 12 H16 M9 16 L7 20 M15 16 L17 20 M12 8 V3',
    OgLIconName.book: 'M4 5 H11 V20 H4 Z M13 5 H20 V20 H13 Z M11 5 H13 V20 H11 Z',
    OgLIconName.clock: 'M9 4 H15 L20 9 V15 L15 20 H9 L4 15 V9 Z M12 8 V12 L15 14',
  };
}

/// 解析缓存（同一 `d` 字符串只解析一次）。
final Map<String, Path> _cache = <String, Path>{};

/// 取某语义的自绘路径（24 × 24 设计网格）。
///
/// 语义缺失时返回空路径（**绝不抛**：设置里的脏图标名不该让界面崩）。
Path ogLVectorPathOf(OgLIconName name) {
  final String? d = OgLVectorIconData.paths[name];
  if (d == null) {
    return Path();
  }
  return _cache.putIfAbsent(d, () => ogLParseVectorPath(d));
}

/// 把 `d` 字符串解析成 [Path]（只支持 M / L / H / V / Z）。
Path ogLParseVectorPath(String d) {
  final Path path = Path();
  final RegExp token = RegExp(r'[MLHVZmlhvz]|-?\d*\.?\d+');
  double x = 0;
  double y = 0;
  double startX = 0;
  double startY = 0;
  String cmd = '';
  final List<double> nums = <double>[];

  void flush() {
    if (nums.isEmpty) {
      return;
    }
    switch (cmd) {
      case 'M':
        for (int i = 0; i + 1 < nums.length; i += 2) {
          x = nums[i];
          y = nums[i + 1];
          if (i == 0) {
            path.moveTo(x, y);
            startX = x;
            startY = y;
          } else {
            path.lineTo(x, y);
          }
        }
      case 'L':
        for (int i = 0; i + 1 < nums.length; i += 2) {
          x = nums[i];
          y = nums[i + 1];
          path.lineTo(x, y);
        }
      case 'H':
        for (final double v in nums) {
          x = v;
          path.lineTo(x, y);
        }
      case 'V':
        for (final double v in nums) {
          y = v;
          path.lineTo(x, y);
        }
      case 'Z':
        path.close();
        x = startX;
        y = startY;
      default:
        break;
    }
    nums.clear();
  }

  for (final RegExpMatch m in token.allMatches(d)) {
    final String s = m.group(0)!;
    if (RegExp(r'[A-Za-z]').hasMatch(s)) {
      flush();
      cmd = s.toUpperCase();
      if (cmd == 'Z') {
        flush();
      }
    } else {
      nums.add(double.parse(s));
    }
  }
  flush();
  return path;
}