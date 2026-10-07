#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 `assets/icon/ogl_icon.svg` 转成 Android **VectorDrawable**（矢量 XML）。

## 为什么 Android 用矢量而不是位图
- 位图要按密度出五套（mdpi…xxxhdpi），每套一个文件，改一次图标要同步五个；
- 矢量只有一份，任何密度、任何放大都清晰，体积还更小；
- 结果是「改 SVG → 三端一致」：Android 矢量、Windows ICO、Linux PNG，
  全部由同一份 `assets/icon/ogl_icon.svg` 现场生成。

## 为什么不用手写 XML
此前 `inject_platform_spec.py` 里是一段**硬编码的矢量前景**，形状与源 SVG
完全不同（盾牌 + 蓝色三角 vs 深色多边形 + 金色双眼）——「唯一事实来源」
名不副实，Android 图标其实从没跟过源图。改成转换后，源图是唯一的。

## 支持范围（与 `desktop_icon.parse_svg` 一致）
`polygon` + `<g fill>` + `linearGradient`；渐变按 SVG 默认的
`objectBoundingBox` 语义换算成 VectorDrawable 的**绝对坐标**。
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from desktop_icon import parse_svg  # noqa: E402  同一套解析，避免两份实现漂移

AAPT_NS = 'http://schemas.android.com/aapt'


def _path_data(points: list[tuple[float, float]]) -> str:
    """多边形顶点 → VectorDrawable 的 `pathData`。"""
    parts = ['M%g,%g' % points[0]]
    parts.extend('L%g,%g' % p for p in points[1:])
    parts.append('Z')
    return ''.join(parts)


def _gradient_attrs(grad: dict, points: list[tuple[float, float]],
                    indent: str) -> str:
    """线性渐变 → Android `<gradient>` 的属性块。

    SVG 的 `x1/y1/x2/y2` 默认是 **objectBoundingBox** 单位（0–1，相对本元素
    自己的包围盒），而 Android 收的是**绝对坐标**。少了这一步换算，渐变会
    整个错位（颜色还在，只是方向/范围不对，很难一眼看出）。
    """
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    minx, miny, maxx, maxy = min(xs), min(ys), max(xs), max(ys)
    w = max(maxx - minx, 1e-9)
    h = max(maxy - miny, 1e-9)

    def sx(v: float) -> float:
        return minx + v * w

    def sy(v: float) -> float:
        return miny + v * h

    stops = grad.get('stops') or []
    if not stops:
        raise ValueError('渐变没有任何 stop')
    if len(stops) > 3:
        # VectorDrawable 的 `<item>` 需要 API 24+；本图标恰好 3 个停靠点，
        # 超出时如实报错而不是悄悄丢掉中间色。
        raise ValueError('渐变停靠点超过 3 个，本转换器只支持 start/center/end')

    def color(value: str) -> str:
        v = value.strip()
        if v.startswith('#') and len(v) == 4:  # #abc → #aabbcc
            v = '#' + ''.join(c * 2 for c in v[1:])
        return v

    attrs = [
        'android:type="linear"',
        'android:startX="%g"' % sx(grad.get('x1', 0.0)),
        'android:startY="%g"' % sy(grad.get('y1', 0.0)),
        'android:endX="%g"' % sx(grad.get('x2', 1.0)),
        'android:endY="%g"' % sy(grad.get('y2', 0.0)),
        'android:startColor="%s"' % color(stops[0][1]),
    ]
    if len(stops) == 3:
        attrs.append('android:centerColor="%s"' % color(stops[1][1]))
    attrs.append('android:endColor="%s"' % color(stops[-1][1]))
    return ('\n' + indent + '    ').join(attrs)


def _paint_ref(layer_fill: str) -> str:
    """从 `url(#id)` 里取出 id（解析出的渐变表以 id 为键）。"""
    value = (layer_fill or '').strip()
    if value.startswith('url('):
        inner = value[4:].rstrip(')').strip().strip('\'"')
        return inner[1:] if inner.startswith('#') else inner
    return value


def to_vector_drawable(
    svg_path: str,
    *,
    width_dp: float,
    height_dp: float,
    viewport: float = 512.0,
    safe_ratio: float = 1.0,
) -> str:
    """生成 VectorDrawable XML。

    [safe_ratio]：图形占画布的比例。自适应图标的**安全区**要求前景落在中心
    约 66%，否则被 Launcher 的遮罩裁掉边角；传 1.0 表示铺满（传统图标用）。
    """
    layers, grads = parse_svg(svg_path)
    if not layers:
        raise ValueError('SVG 里没有解析到任何图层：%s' % svg_path)

    scale = 1.0
    tx = 0.0
    ty = 0.0
    if safe_ratio < 1.0:
        xs = [p[0] for layer in layers for p in layer['points']]
        ys = [p[1] for layer in layers for p in layer['points']]
        art_w = max(max(xs) - min(xs), 1e-9)
        art_h = max(max(ys) - min(ys), 1e-9)
        cx = (max(xs) + min(xs)) / 2.0
        cy = (max(ys) + min(ys)) / 2.0
        target = viewport * safe_ratio
        scale = min(target / art_w, target / art_h)
        # 缩放以原点为中心 → 再把图形中心挪到画布中心。
        # ★ X/Y 必须**分别**算：源图的重心未必在画布正中（本图 cx=256、
        #   cy=272），只算 X 再套用到 Y，图形就会纵向偏移（约 3%），
        #   在自适应图标的安全区里更明显。
        tx = viewport / 2.0 - cx * scale
        ty = viewport / 2.0 - cy * scale

    paths: list[str] = []
    for layer in layers:
        points = layer['points']
        if len(points) < 3:
            continue
        grad = grads.get(_paint_ref(layer['fill']))
        if grad is None:
            raise ValueError(
                '图层填充 %r 找不到对应渐变（本转换器只支持 '
                'linearGradient，不做纯色/图案）' % layer['fill'])
        fills = (
            '            <aapt:attr name="android:fillColor">\n'
            '                <gradient\n'
            '                    %s />\n'
            '            </aapt:attr>' % _gradient_attrs(grad, points, '            ')
        )
        paths.append(
            '        <path\n'
            '            android:pathData="%s">\n%s\n'
            '        </path>' % (_path_data(points), fills)
        )

    body = '\n'.join(paths)
    if scale != 1.0 or tx != 0.0 or ty != 0.0:
        body = (
            '    <group\n'
            '        android:scaleX="%g"\n'
            '        android:scaleY="%g"\n'
            '        android:translateX="%g"\n'
            '        android:translateY="%g">\n%s\n    </group>'
            % (scale, scale, tx, ty, body)
        )

    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- OGL_PLATFORM_SPEC icon -->\n'
        '<!-- 由 tool/svg_vector.py 从 assets/icon/ogl_icon.svg 生成，请勿手改。 -->\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    xmlns:aapt="%s"\n'
        '    android:width="%gdp"\n'
        '    android:height="%gdp"\n'
        '    android:viewportWidth="%g"\n'
        '    android:viewportHeight="%g">\n'
        '%s\n'
        '</vector>\n'
        % (AAPT_NS, width_dp, height_dp, viewport, viewport, body)
    )


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description='SVG → Android VectorDrawable')
    ap.add_argument('svg')
    ap.add_argument('-o', '--out', help='输出文件（缺省打印到 stdout）')
    ap.add_argument('--width-dp', type=float, default=108.0)
    ap.add_argument('--height-dp', type=float, default=108.0)
    ap.add_argument('--safe-ratio', type=float, default=1.0)
    args = ap.parse_args()
    xml = to_vector_drawable(
        args.svg,
        width_dp=args.width_dp,
        height_dp=args.height_dp,
        safe_ratio=args.safe_ratio,
    )
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as handle:
            handle.write(xml)
        print('已写出 %s（%d 字节）' % (args.out, len(xml)))
    else:
        sys.stdout.write(xml)
    return 0


if __name__ == '__main__':
    sys.exit(main())
