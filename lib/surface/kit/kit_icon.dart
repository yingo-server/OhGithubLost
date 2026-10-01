/// OGL Kit · 图标（**自绘矢量**，Primer Octicons 的"更概念、更尖锐"版）。
///
/// 用法：`OgLIcon(name: OgLIconName.star, size: 16)`。
///
/// 与旧实现的区别：W3 之前这里是 `Icon(ogL.icon(name))`，渲染的是
/// **Material 字形**；现在是把 `lib/surface/icons/og_l_vector_icon.dart`
/// 里的手写路径画出来 —— 零字体、零外部资源，端点 `butt`、拐角 `miter`
/// （不圆滑，更锐）。全仓库已无任何 Material 字形图标调用。
///
/// 风格跟随主题包（`OgLTheme.iconStyle`）：细线 / 标准 / 实心。
library;

import 'package:flutter/material.dart';

import '../icons/og_l_vector_icon.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 自绘矢量图标。
class OgLIcon extends StatelessWidget {
  /// 创建图标。
  const OgLIcon({
    required this.name,
    this.size,
    this.color,
    this.strokeWidth,
    super.key,
  });

  /// 语义名（界面唯一允许的图标引用方式）。
  final OgLIconName name;

  /// 边长（正方形；缺省 20，也允许直接喂 `textTheme.x?.fontSize`）。
  final double? size;

  /// 颜色（默认取 `palette.text`）。
  final Color? color;

  /// 线宽（24 网格下的设计值；默认取主题包的 `iconStroke`）。
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final double design = strokeWidth ?? ogL.iconStroke;
    final bool solid = ogL.iconStyle == OgLIconStyle.solid;
    final double side = size ?? 20;

    return SizedBox(
      width: side,
      height: side,
      child: CustomPaint(
        painter: _OgLIconPainter(
          name: name,
          color: color ?? ogL.palette.text,
          strokeWidth: design * side / 24,
          fill: solid,
        ),
      ),
    );
  }
}

class _OgLIconPainter extends CustomPainter {
  _OgLIconPainter({
    required this.name,
    required this.color,
    required this.strokeWidth,
    required this.fill,
  });

  final OgLIconName name;
  final Color color;
  final double strokeWidth;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final Path base = ogLVectorPathOf(name);
    if (base.getBounds().isEmpty) {
      return; // 未知语义：什么都不画（不抛、不崩）。
    }
    final double scale = size.width / 24;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // 线宽写在 24 网格坐标里，再随画布缩放 ⇒ 任何尺寸都等比例。
      ..strokeWidth = strokeWidth / scale
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    canvas.save();
    canvas.scale(scale, scale);
    if (fill) {
      canvas.drawPath(
        base,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
    }
    canvas.drawPath(base, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OgLIconPainter old) =>
      old.name != name ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.fill != fill;
}