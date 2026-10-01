/// OGL Kit · 骨架屏 —— 对齐 Primer Skeleton（avatar / text / box）。
///
/// 动效：轻微呼吸（900ms 反向循环）；系统"减少动效"开启时静止。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// 骨架块。
class OgLSkeletonBox extends StatefulWidget {
  /// 创建骨架块。
  const OgLSkeletonBox({
    this.width = double.infinity,
    this.height = 12,
    this.radius,
    super.key,
  });

  /// 宽度。
  final double width;

  /// 高度。
  final double height;

  /// 圆角（默认取令牌小圆角）。
  final double? radius;

  @override
  State<OgLSkeletonBox> createState() => _OgLSkeletonBoxState();
}

class _OgLSkeletonBoxState extends State<OgLSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final base = ogL.palette.surfaceAlt;
    final highlight = ogL.palette.border;
    final radius = widget.radius ?? ogL.tokens.radius(OgLRadius.sm);
    if (ogL.tokens.reducedMotion) {
      return _buildBox(base, radius);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) => _buildBox(
        Color.lerp(base, highlight, 0.6 * _controller.value)!,
        radius,
      ),
    );
  }

  Widget _buildBox(Color color, double radius) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// 多行文本骨架。
class OgLSkeletonText extends StatelessWidget {
  /// 创建文本骨架。
  const OgLSkeletonText({this.lines = 3, super.key});

  /// 行数。
  final int lines;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    // 末行短一些更像"段落"，长度 160 由间距刻度推出（32 × 5）。
    final double shortWidth = ogL.tokens.space(OgLSpacing.xxl * 5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < lines; i++) ...<Widget>[
          if (i > 0) SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
          OgLSkeletonBox(
            height: 12,
            width: i == lines - 1 ? shortWidth : double.infinity,
          ),
        ],
      ],
    );
  }
}

/// 头像骨架（圆形）。
class OgLSkeletonAvatar extends StatelessWidget {
  /// 创建头像骨架。
  const OgLSkeletonAvatar({this.size = 32, super.key});

  /// 直径。
  final double size;

  @override
  Widget build(BuildContext context) =>
      OgLSkeletonBox(width: size, height: size, radius: size / 2);
}
