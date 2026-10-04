#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 桌面图标光栅化（**零第三方依赖**）。

## 为什么自己写而不是拉 Pillow / cairosvg
CI 的 runner 与容器里未必有图形栈，装一套 cairo / Pillow 既慢又脆。
图标的几何来源是 `assets/icon/ogl_icon.svg`（唯一事实来源），形状只有
**3 个多边形 + 2 条渐变**——用扫描线填充 + PNG 自编码完全够，且**确定**：
同样的输入在任何机器上产出**逐字节相同**的文件。

## 支持
- `render_rgba(size)`：把 SVG 渲染成 RGBA 像素（抗锯齿：竖直 4 倍超采样）。
- `encode_png(rgba, size)`：写标准 PNG（RGBA8）。
- `encode_ico(png, size)`：把 PNG 塞进 ICO（256 用 PNG 内嵌，Vista+ 通用）。

坐标：SVG `viewBox="0 0 512 512"`，渲染时按 `size/512` 缩放。
"""

from __future__ import annotations

import re
import struct
import zlib

SVG_SIZE = 512.0


def _parse_svg(path: str) -> tuple[list[dict], dict[str, list[tuple[float, str]]]]:
    """从 SVG 里解析出多边形与渐变（不引依赖，纯正则）。"""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    grads: dict[str, dict] = {}
    for gid, attrs, body in re.findall(
        r'<linearGradient[^>]*id="([^"]+)"([^>]*)>(.*?)</linearGradient>',
        text,
        re.S,
    ):
        def _num(name: str, default: float) -> float:
            m = re.search(r'%s="([-\d.]+)"' % name, attrs)
            return float(m.group(1)) if m else default

        stops = [
            (float(off), color)
            for off, color in re.findall(
                r'<stop[^>]*offset="([\d.]+)"[^>]*stop-color="([^"]+)"', body
            )
        ]
        stops.sort(key=lambda item: item[0])
        grads[gid] = {
            "x1": _num("x1", 0.0),
            "y1": _num("y1", 0.0),
            "x2": _num("x2", 1.0),
            "y2": _num("y2", 0.0),
            "stops": stops,
        }

    layers: list[dict] = []
    # 带 fill 的多边形；`<g fill="...">` 作为子元素的默认填充。
    for match in re.finditer(
        r'(?:<g[^>]*fill="([^"]+)"[^>]*>(.*?)</g>)|(?:<polygon[^>]*fill="([^"]+)"[^>]*/>)',
        text,
        re.S,
    ):
        group_fill, group_body, lone_fill = match.groups()
        if group_fill is not None:
            for points in re.findall(r'points="([^"]+)"', group_body):
                layers.append({"fill": group_fill, "points": _points(points)})
        elif lone_fill is not None:
            points = re.search(r'points="([^"]+)"', match.group(0))
            if points is not None:
                layers.append({"fill": lone_fill, "points": _points(points.group(1))})
    return layers, grads


def _points(raw: str) -> list[tuple[float, float]]:
    nums = [float(v) for v in re.findall(r"-?[\d.]+", raw)]
    return [(nums[i], nums[i + 1]) for i in range(0, len(nums) - 1, 2)]


def _hex(color: str) -> tuple[int, int, int]:
    value = color.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def _gradient_at(grad: dict, x: float, y: float, bbox: tuple[float, float, float, float]) -> tuple[int, int, int]:
    """按 objectBoundingBox 规则求渐变颜色（`t` 是投影到渐变轴上的比例）。"""
    minx, miny, maxx, maxy = bbox
    dx = max(maxx - minx, 1e-9)
    dy = max(maxy - miny, 1e-9)
    ax = grad["x2"] - grad["x1"]
    ay = grad["y2"] - grad["y1"]
    denom = ax * ax + ay * ay
    if denom < 1e-12:
        t = 0.0
    else:
        px = (x - minx) / dx - grad["x1"]
        py = (y - miny) / dy - grad["y1"]
        t = (px * ax + py * ay) / denom
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)

    stops = grad["stops"]
    if not stops:
        return (0, 0, 0)
    prev = stops[0]
    for cur in stops:
        if t <= cur[0]:
            span = cur[0] - prev[0]
            k = 0.0 if span <= 1e-9 else (t - prev[0]) / span
            c0, c1 = _hex(prev[1]), _hex(cur[1])
            return tuple(int(round(c0[i] + (c1[i] - c0[i]) * k)) for i in range(3))  # type: ignore[return-value]
        prev = cur
    return _hex(stops[-1][1])


def _coverage(points: list[tuple[float, float]], size: int, scale: float, sub_rows: int = 4) -> list[float]:
    """扫描线填充，返回每个像素的抗锯齿覆盖度（0..1）。"""
    cover = [0.0] * (size * size)
    count = len(points)
    step = scale / sub_rows
    for py in range(size):
        acc = [0.0] * size
        for s in range(sub_rows):
            y = py * scale + (s + 0.5) * step
            crossings: list[float] = []
            for i in range(count):
                x1, y1 = points[i]
                x2, y2 = points[(i + 1) % count]
                if (y1 <= y < y2) or (y2 <= y < y1):
                    crossings.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
            crossings.sort()
            for j in range(0, len(crossings) - 1, 2):
                xa = crossings[j] / scale
                xb = crossings[j + 1] / scale
                if xb <= 0 or xa >= size:
                    continue
                xa = 0.0 if xa < 0 else xa
                xb = float(size) if xb > size else xb
                ia, ib = int(xa), int(xb)
                if ia == ib:
                    if ia < size:
                        acc[ia] += xb - xa
                    continue
                acc[ia] += ia + 1 - xa
                for k in range(ia + 1, ib):
                    acc[k] += 1.0
                if ib < size:
                    acc[ib] += xb - ib
        base = py * size
        for px in range(size):
            cover[base + px] = acc[px] / sub_rows
    return cover


def render_rgba(svg_path: str, size: int) -> bytes:
    """渲染为 RGBA（背景透明）。"""
    layers, grads = _parse_svg(svg_path)
    scale = SVG_SIZE / float(size)
    out = bytearray(size * size * 4)  # 全透明

    for layer in layers:
        points = layer["points"]
        grad = grads.get(layer["fill"].strip())
        if grad is None:
            continue
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        bbox = (min(xs), min(ys), max(xs), max(ys))
        cover = _coverage(points, size, scale)
        for py in range(size):
            base = py * size
            for px in range(size):
                a = cover[base + px]
                if a <= 0.0:
                    continue
                sx = (px + 0.5) * scale
                sy = (py + 0.5) * scale
                r, g, b = _gradient_at(grad, sx, sy, bbox)
                idx = (base + px) * 4
                sr, sg, sb = a, a, a
                dr = out[idx] / 255.0
                dg = out[idx + 1] / 255.0
                db = out[idx + 2] / 255.0
                da = out[idx + 3] / 255.0
                oa = sr + da * (1 - sr)
                if oa <= 0:
                    continue
                out[idx] = int(round(255 * (r / 255.0 * sr + dr * da * (1 - sr)) / oa))
                out[idx + 1] = int(round(255 * (g / 255.0 * sr + dg * da * (1 - sr)) / oa))
                out[idx + 2] = int(round(255 * (b / 255.0 * sr + db * da * (1 - sr)) / oa))
                out[idx + 3] = int(round(255 * oa))
    return bytes(out)


def _chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def encode_png(rgba: bytes, size: int) -> bytes:
    """RGBA → PNG（无滤波，压缩级别 9）。"""
    stride = size * 4
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        raw += rgba[y * stride : (y + 1) * stride]
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )


def encode_ico(png: bytes, size: int) -> bytes:
    """PNG → 单帧 ICO（256 用 0 表示，PNG 内嵌，Vista+ 通用）。"""
    dim = 0 if size >= 256 else size
    header = struct.pack("<HHH", 0, 1, 1)
    entry = struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(png), 22)
    return header + entry + png


def main() -> int:
    import argparse
    import os

    parser = argparse.ArgumentParser(description="OGL 桌面图标生成")
    parser.add_argument("--svg", required=True)
    parser.add_argument("--png", help="输出的 PNG 路径")
    parser.add_argument("--png-size", type=int, default=2048)
    parser.add_argument("--ico", help="输出的 ICO 路径")
    parser.add_argument("--ico-size", type=int, default=256)
    args = parser.parse_args()

    if args.png:
        rgba = render_rgba(args.svg, args.png_size)
        with open(args.png, "wb") as handle:
            handle.write(encode_png(rgba, args.png_size))
        print("[图标] PNG %dx%d → %s（%d 字节）" % (args.png_size, args.png_size, args.png, os.path.getsize(args.png)))

    if args.ico:
        rgba = render_rgba(args.svg, args.ico_size)
        png = encode_png(rgba, args.ico_size)
        with open(args.ico, "wb") as handle:
            handle.write(encode_ico(png, args.ico_size))
        print("[图标] ICO %dx%d → %s（%d 字节）" % (args.ico_size, args.ico_size, args.ico, os.path.getsize(args.ico)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
