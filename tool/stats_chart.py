#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 仓库统计曲线（星标 / 提交数）—— **带坐标系、刻度与单位**的 PNG 折线图。

## 为什么重写（5.3）
旧实现有三个硬伤，读图会被误导：

1. **纵轴按各自 min..max 拉伸**：3→4 也能画成"垂直暴涨"，且星标图与提交图
   各自满高，**量纲不同却看起来同量级**；
2. **没有坐标系**：无刻度、无单位、无标题、无日期，读者不知道数值范围与时间跨度；
3. **横轴按索引等距**：采样间隔不均时时间被拉伸/压缩，不是真实时间轴。

新版约定（简单、稳定、可核对）：
- **纵轴从 0 起**（不截断），上限取"整齐"刻度（1/2/2.5/5 × 10^n），5 条刻度线并标注数值；
- **横轴是真实时间（UTC）**，标注 `MM-DD HH:MM`，首尾与中间刻度对齐数据；
- 图内绘制**标题行**：`指标名（单位）+ 最新值 + 点数 + 数据来源`；
- 坐标轴/网格/刻度/文字全部自绘：**仍然零第三方依赖**（zlib 手写 PNG + 内置 5×7 点阵字体），
  Actions 里零安装运行；
- 数据点过密时**等距降采样**（保留首尾），避免折线糊成一片；
- 兼容旧 `history.json`（缺字段/坏时间戳的点跳过并留痕，不炸）。

## 用法
    python3 tool/stats_chart.py --repo owner/name --history stats/history.json --out-dir stats
    python3 tool/stats_chart.py --selftest      # 不需要网络：核对刻度/时间映射/降采样数学

## 环境变量
    GH_TOKEN / GITHUB_TOKEN  具备读取权限的令牌（Actions 用 secrets.GITHUB_TOKEN）。
"""

import argparse
import json
import os
import re
import struct
import sys
import urllib.error
import urllib.request
import zlib
from datetime import datetime, timezone

API = 'https://api.github.com'

# ── 版面（像素）────────────────────────────────────────────────────────────
WIDTH = 800
HEIGHT = 320
MARGIN_LEFT = 74
MARGIN_RIGHT = 18
MARGIN_TOP = 44
MARGIN_BOTTOM = 46

COLOR_BG = (255, 255, 255)
COLOR_AXIS = (154, 165, 177)
COLOR_GRID = (232, 236, 241)
COLOR_TEXT = (72, 82, 94)
COLOR_MUTED = (138, 148, 160)
COLOR_STAR = (9, 105, 218)
COLOR_COMMIT = (45, 164, 78)

GLYPH_W = 5
GLYPH_H = 7
GLYPH_GAP = 1

# ── 5×7 点阵字体（1 = 落墨）────────────────────────────────────────────────
# 行数固定 7、列宽固定 5；只需要图表用到的大写字母 / 数字 / 少量符号。
_FONT_ROWS = {
    '0': '01110 10001 10011 10101 11001 10001 01110',
    '1': '00100 01100 00100 00100 00100 00100 01110',
    '2': '01110 10001 00001 00010 00100 01000 11111',
    '3': '11111 00010 00100 00010 00001 10001 01110',
    '4': '00010 00110 01010 10010 11111 00010 00010',
    '5': '11111 10000 11110 00001 00001 10001 01110',
    '6': '00110 01000 10000 11110 10001 10001 01110',
    '7': '11111 00001 00010 00100 01000 01000 01000',
    '8': '01110 10001 10001 01110 10001 10001 01110',
    '9': '01110 10001 10001 01111 00001 00010 01100',
    'A': '01110 10001 10001 11111 10001 10001 10001',
    'B': '11110 10001 10001 11110 10001 10001 11110',
    'C': '01110 10001 10000 10000 10000 10001 01110',
    'D': '11100 10010 10001 10001 10001 10010 11100',
    'E': '11111 10000 10000 11110 10000 10000 11111',
    'F': '11111 10000 10000 11110 10000 10000 10000',
    'G': '01110 10001 10000 10111 10001 10001 01111',
    'H': '10001 10001 10001 11111 10001 10001 10001',
    'I': '01110 00100 00100 00100 00100 00100 01110',
    'J': '00111 00010 00010 00010 00010 10010 01100',
    'K': '10001 10010 10100 11000 10100 10010 10001',
    'L': '10000 10000 10000 10000 10000 10000 11111',
    'M': '10001 11011 10101 10101 10001 10001 10001',
    'N': '10001 11001 10101 10011 10001 10001 10001',
    'O': '01110 10001 10001 10001 10001 10001 01110',
    'P': '11110 10001 10001 11110 10000 10000 10000',
    'Q': '01110 10001 10001 10001 10101 10010 01101',
    'R': '11110 10001 10001 11110 10100 10010 10001',
    'S': '01111 10000 10000 01110 00001 00001 11110',
    'T': '11111 00100 00100 00100 00100 00100 00100',
    'U': '10001 10001 10001 10001 10001 10001 01110',
    'V': '10001 10001 10001 10001 10001 01010 00100',
    'W': '10001 10001 10001 10101 10101 11011 10001',
    'X': '10001 10001 01010 00100 01010 10001 10001',
    'Y': '10001 10001 01010 00100 00100 00100 00100',
    'Z': '11111 00001 00010 00100 01000 10000 11111',
    '-': '00000 00000 00000 11111 00000 00000 00000',
    '.': '00000 00000 00000 00000 00000 01100 01100',
    ':': '00000 01100 01100 00000 01100 01100 00000',
    '/': '00001 00010 00010 00100 01000 01000 10000',
    '(': '00010 00100 01000 01000 01000 00100 00010',
    ')': '01000 00100 00010 00010 00010 00100 01000',
    '+': '00000 00100 00100 11111 00100 00100 00000',
    '%': '11001 11010 00010 00100 01000 01011 10011',
    ',': '00000 00000 00000 00000 01100 01100 11000',
    ' ': '00000 00000 00000 00000 00000 00000 00000',
}


def _font_glyph(char):
    rows = _FONT_ROWS.get(char.upper(), _FONT_ROWS[' '])
    return [[1 if bit == '1' else 0 for bit in row] for row in rows.split()]


# ── 画布 / 基本绘制 ────────────────────────────────────────────────────────
def _canvas(width, height, color):
    row = bytes(color) * width
    return [bytearray(row) for _ in range(height)]


def _rect(rows, x0, y0, x1, y1, color):
    height = len(rows)
    width = len(rows[0]) // 3
    for y in range(max(0, int(y0)), min(height, int(y1))):
        for x in range(max(0, int(x0)), min(width, int(x1))):
            rows[y][3 * x:3 * x + 3] = bytes(color)


def _line(rows, x0, y0, x1, y1, color, thick=2):
    steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(steps):
        t = i / float(steps)
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        _rect(rows, x, y, x + thick, y + thick, color)


def text_width(text):
    if not text:
        return 0
    return len(text) * (GLYPH_W + GLYPH_GAP) - GLYPH_GAP


def _text(rows, x, y, text, color, scale=1):
    cursor = x
    for char in text:
        glyph = _font_glyph(char)
        for gy, line in enumerate(glyph):
            for gx, ink in enumerate(line):
                if not ink:
                    continue
                _rect(rows, cursor + gx * scale, y + gy * scale,
                      cursor + (gx + 1) * scale, y + (gy + 1) * scale, color)
        cursor += (GLYPH_W + GLYPH_GAP) * scale


def _write_png(path, rows):
    width = len(rows[0]) // 3
    height = len(rows)
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    blob = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'wb') as handle:
        handle.write(blob)


# ── 坐标轴数学（纯函数，可单测）────────────────────────────────────────────
def nice_axis_max(value):
    """把数据上限抬到"整齐"刻度：1 / 2 / 2.5 / 5 × 10^n（至少 1）。"""
    if value <= 0:
        return 1.0
    exponent = 0
    scaled = float(value)
    while scaled >= 10:
        scaled /= 10.0
        exponent += 1
    while scaled < 1:
        scaled *= 10.0
        exponent -= 1
    for step in (1.0, 2.0, 2.5, 5.0, 10.0):
        if scaled <= step:
            return step * (10 ** exponent)
    return 10.0 * (10 ** exponent)


def axis_ticks(axis_max, count=5):
    """0..axis_max 等分刻度（含 0 与上限）。"""
    if count < 2:
        count = 2
    return [axis_max * i / (count - 1) for i in range(count)]


def format_value(value):
    """刻度数值：整数不带小数点，小数最多 1 位。"""
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return ('%.1f' % value).rstrip('0').rstrip('.')


def format_time(value, with_date=True):
    """UTC 时间戳 → `MM-DD HH:MM`（跨天信息保留；同日也带日期以免误读）。"""
    stamp = datetime.fromtimestamp(value, tz=timezone.utc)
    if with_date:
        return stamp.strftime('%m-%d %H:%M')
    return stamp.strftime('%H:%M')


def x_positions(times, left, width):
    """时间 → 像素（**真实时间轴**：间隔按秒数比例，而非索引等距）。

    单点或时间无跨度时落在中心。
    """
    if not times:
        return []
    lo, hi = times[0], times[-1]
    span = hi - lo
    if span <= 0:
        return [left + width / 2.0 for _ in times]
    return [left + (t - lo) / float(span) * width for t in times]


def downsample(values, limit):
    """等距降采样（保留首尾），避免 500 点糊成一片。"""
    count = len(values)
    if count <= limit or limit <= 2:
        return values
    step = (count - 1) / float(limit - 1)
    return [values[int(round(i * step))] for i in range(limit)]


def downsample_points(points, limit):
    return downsample(points, limit)


# ── 数据抓取 ──────────────────────────────────────────────────────────────
def _request(path, token):
    request = urllib.request.Request(API + path)
    request.add_header('Authorization', 'Bearer ' + token)
    request.add_header('Accept', 'application/vnd.github+json')
    request.add_header('X-GitHub-Api-Version', '2022-11-28')
    request.add_header('User-Agent', 'ogl-stats')
    return urllib.request.urlopen(request, timeout=60)


def fetch_stars(repo, token):
    with _request('/repos/' + repo, token) as response:
        data = json.loads(response.read().decode('utf-8'))
    return int(data.get('stargazers_count', 0))


def fetch_commits(repo, token):
    """提交总数：`per_page=1` 时 Link 头 `rel="last"` 的 page 即为总数。"""
    with _request('/repos/%s/commits?per_page=1' % repo, token) as response:
        link = response.headers.get('Link', '')
        body = json.loads(response.read().decode('utf-8'))
    if link:
        match = re.search(r'[?&]page=(\d+)>;\s*rel="last"', link)
        if match:
            return int(match.group(1))
    return len(body) if isinstance(body, list) else 0


# ── 历史读写（兼容旧结构）──────────────────────────────────────────────────
def load_history(path):
    """读取历史点；坏点跳过并留痕（**不因一条坏数据丢掉整段历史**）。"""
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding='utf-8') as handle:
            data = json.load(handle)
    except Exception as error:  # noqa: BLE001
        print('history 读取失败，按空历史处理：%s' % error, file=sys.stderr)
        return []
    if not isinstance(data, list):
        print('history 结构不是数组，按空历史处理', file=sys.stderr)
        return []
    points = []
    skipped = 0
    for item in data:
        point = parse_point(item)
        if point is None:
            skipped += 1
            continue
        points.append(point)
    if skipped:
        print('history 跳过 %d 个坏点' % skipped, file=sys.stderr)
    points.sort(key=lambda p: p['ts'])
    return points


def parse_point(item):
    """解析一个历史点（容错）：返回 `{'ts','iso','stars','commits'}` 或 None。"""
    if not isinstance(item, dict):
        return None
    raw_time = item.get('t') or item.get('ts') or item.get('time')
    if not isinstance(raw_time, str):
        return None
    try:
        stamp = datetime.fromisoformat(raw_time.replace('Z', '+00:00'))
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return {
        'ts': stamp.timestamp(),
        'iso': stamp.astimezone(timezone.utc)
        .replace(microsecond=0).isoformat().replace('+00:00', 'Z'),
        'stars': int(item.get('stars') or 0),
        'commits': int(item.get('commits') or 0),
    }


def write_history(path, points):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    payload = [{'t': p['iso'], 'stars': p['stars'], 'commits': p['commits']}
               for p in points]
    with open(path, 'w', encoding='utf-8') as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write('\n')


# ── 渲染 ─────────────────────────────────────────────────────────────────
def render_chart(points, key, color, path, title, unit, source):
    """把一串历史点渲染成**带坐标系**的 PNG。"""
    rows = _canvas(WIDTH, HEIGHT, COLOR_BG)
    plot_left = MARGIN_LEFT
    plot_top = MARGIN_TOP
    plot_w = WIDTH - MARGIN_LEFT - MARGIN_RIGHT
    plot_h = HEIGHT - MARGIN_TOP - MARGIN_BOTTOM
    plot_bottom = plot_top + plot_h

    times = [p['ts'] for p in points]
    values = [int(p.get(key, 0)) for p in points]

    # 纵轴：从 0 起 + 整齐上限（不截断、不按极值拉伸）
    axis_max = nice_axis_max(max(values) if values else 0)

    def y_of(value):
        if axis_max <= 0:
            return plot_bottom
        return plot_bottom - (value / axis_max) * plot_h

    # 标题行：指标（单位）+ 最新值 + 点数
    last_value = values[-1] if values else 0
    _text(rows, plot_left, 14, title, COLOR_TEXT)
    _text(rows, plot_left, 28,
          'LAST %s %s   POINTS %s   SOURCE %s'
          % (format_value(last_value), unit, len(points), source),
          COLOR_MUTED)

    # 网格 + 纵轴刻度（数值）
    for tick in axis_ticks(axis_max):
        y = int(round(y_of(tick)))
        _rect(rows, plot_left, y, plot_left + plot_w, y + 1, COLOR_GRID)
        label = format_value(tick)
        _text(rows, plot_left - 10 - text_width(label), y - 3, label, COLOR_MUTED)

    # 轴框
    _rect(rows, plot_left, plot_top, plot_left + plot_w, plot_top + 1, COLOR_AXIS)
    _rect(rows, plot_left, plot_bottom, plot_left + plot_w, plot_bottom + 1,
          COLOR_AXIS)
    _rect(rows, plot_left, plot_top, plot_left + 1, plot_bottom + 1, COLOR_AXIS)

    # 纵轴单位（写在轴顶：`COUNT` 之类，明确量纲）
    _text(rows, 6, plot_top - 10, unit, COLOR_MUTED)

    # 横轴：真实时间刻度（首/中/尾）
    if times:
        span = times[-1] - times[0]
        if span <= 0:
            ticks_time = [times[0]] * 3
        else:
            ticks_time = [times[0], times[0] + span / 2.0, times[-1]]
        for stamp in ticks_time:
            x = x_positions([stamp, times[-1]], plot_left, plot_w)[0] \
                if span <= 0 else plot_left + (stamp - times[0]) / span * plot_w
            label = format_time(stamp)
            width = text_width(label)
            x_pos = int(min(max(plot_left, x - width / 2.0),
                            plot_left + plot_w - width))
            _text(rows, x_pos, plot_bottom + 8, label, COLOR_MUTED)
        _text(rows, plot_left, plot_bottom + 24, 'TIME (UTC)  Y-AXIS FROM 0',
              COLOR_MUTED)

    # 数据：横轴按真实时间、纵轴按数值
    if len(points) >= 2:
        sampled = downsample_points(points, max(2, plot_w // 2))
        xs = x_positions([p['ts'] for p in sampled], plot_left, plot_w)
        ys = [y_of(int(p.get(key, 0))) for p in sampled]
        for i in range(len(sampled) - 1):
            _line(rows, xs[i], ys[i], xs[i + 1], ys[i + 1], color)
        # 最新点加粗标出来（读者一眼看到"现在是多少"）
        _rect(rows, int(xs[-1]) - 3, int(ys[-1]) - 3, int(xs[-1]) + 4,
              int(ys[-1]) + 4, color)
    elif points:
        x = x_positions(times, plot_left, plot_w)[0]
        y = y_of(values[0])
        _rect(rows, int(x) - 3, int(y) - 3, int(x) + 4, int(y) + 4, color)

    _write_png(path, rows)


# ── 自检（不联网，供 CI 直接跑）────────────────────────────────────────────
def selftest():
    failures = []

    def check(name, condition):
        if not condition:
            failures.append(name)

    # 刻度上限：永远 ≥ 数据、且是 1/2/2.5/5×10^n
    for value in (0, 1, 3, 42, 99, 1234, 0.4):
        axis_max = nice_axis_max(value)
        check('nice_axis_max(%s) >= value' % value, axis_max >= value - 1e-9)
        check('nice_axis_max(%s) 为正' % value, axis_max > 0)
    # 计数类（整数）总是不小于 1；小数输入仍应按同一套阶梯给值。
    for count in (0, 1, 3, 42, 99, 1234):
        check('nice_axis_max(%d) >= 1' % count, nice_axis_max(count) >= 1)
    check('nice_axis_max(42) == 50', nice_axis_max(42) == 50)
    check('nice_axis_max(1234) == 2000', nice_axis_max(1234) == 2000)
    check('nice_axis_max(0.4) == 0.5', abs(nice_axis_max(0.4) - 0.5) < 1e-9)

    # 刻度：5 条、含 0 与上限、单调
    ticks = axis_ticks(nice_axis_max(42))
    check('刻度条数 == 5', len(ticks) == 5)
    check('刻度从 0 起', abs(ticks[0]) < 1e-9)
    check('刻度到上限', abs(ticks[-1] - nice_axis_max(42)) < 1e-9)
    check('刻度单调', all(ticks[i] < ticks[i + 1] for i in range(len(ticks) - 1)))

    # 时间轴：真实比例（不等距时间 → 不等距像素），且单调
    xs = x_positions([0.0, 10.0, 100.0], 0.0, 100.0)
    check('时间轴首端对齐 0', abs(xs[0]) < 1e-9)
    check('时间轴末端对齐宽度', abs(xs[-1] - 100.0) < 1e-9)
    check('时间轴按真实间隔（10% 处）', abs(xs[1] - 10.0) < 1e-6)
    check('时间轴单调', xs[0] < xs[1] < xs[2])
    check('单点落在中心', abs(x_positions([5.0], 0.0, 100.0)[0] - 50.0) < 1e-9)

    # 降采样：保留首尾、不超限
    data = list(range(500))
    sampled = downsample(data, 100)
    check('降采样条数 <= 上限', len(sampled) <= 100)
    check('降采样保留首尾', sampled[0] == 0 and sampled[-1] == 499)
    check('不超限时原样返回', downsample([1, 2, 3], 10) == [1, 2, 3])

    # 历史点容错
    check('坏时间戳被拒', parse_point({'t': 'not-a-time', 'stars': 1}) is None)
    check('缺字段被拒', parse_point({'stars': 1}) is None)
    point = parse_point({'t': '2026-10-04T10:00:00Z', 'stars': '7'})
    check('字符串数字容错', point is not None and point['stars'] == 7)

    # 字体：图表用到的字符都在
    for char in 'STARS COMMITS LAST POINTS SOURCE TIME (UTC) Y-AXIS FROM 0-:.,/%+':
        if char == ' ':
            continue
        check('字体含 %r' % char, char.upper() in _FONT_ROWS)

    # 渲染一张（含单点与多点），并检查 PNG 头
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        single = [{'ts': 1.0, 'iso': 'x', 'stars': 3, 'commits': 1}]
        many = [{'ts': float(i * 600), 'iso': 'x',
                 'stars': i, 'commits': i * 2} for i in range(200)]
        for name, data_points in (('single', single), ('many', many)):
            path = os.path.join(tmp, '%s.png' % name)
            render_chart(data_points, 'stars', COLOR_STAR, path,
                         'STARS (COUNT)', 'COUNT', 'GITHUB API')
            with open(path, 'rb') as handle:
                head = handle.read(24)
            check('%s.png 是 PNG' % name, head[:8] == b'\x89PNG\r\n\x1a\n')
            check('%s.png 尺寸正确' % name,
                  struct.unpack('>II', head[16:24]) == (WIDTH, HEIGHT))

    if failures:
        for item in failures:
            print('FAIL %s' % item, file=sys.stderr)
        print('自检失败：%d 项' % len(failures), file=sys.stderr)
        return 1
    print('自检通过：刻度 / 时间轴 / 降采样 / 容错 / 字体 / PNG 输出全部符合预期')
    return 0


# ── 主流程 ───────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo')
    parser.add_argument('--history')
    parser.add_argument('--out-dir')
    parser.add_argument('--max-points', type=int, default=2000)
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()

    if args.selftest:
        return selftest()
    if not (args.repo and args.history and args.out_dir):
        parser.error('需要 --repo / --history / --out-dir（或 --selftest）')

    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN') or ''
    if not token:
        print('缺少 GH_TOKEN / GITHUB_TOKEN', file=sys.stderr)
        return 2

    try:
        stars = fetch_stars(args.repo, token)
        commits = fetch_commits(args.repo, token)
    except urllib.error.HTTPError as error:
        print('接口请求失败：HTTP %s' % error.code, file=sys.stderr)
        return 3

    points = load_history(args.history)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    points.append({
        'ts': now.timestamp(),
        'iso': now.isoformat().replace('+00:00', 'Z'),
        'stars': stars,
        'commits': commits,
    })
    if len(points) > args.max_points:
        points = points[-args.max_points:]

    write_history(args.history, points)

    render_chart(points, 'stars', COLOR_STAR,
                 os.path.join(args.out_dir, 'star-history.png'),
                 'STARS (COUNT)', 'COUNT', 'GITHUB API')
    render_chart(points, 'commits', COLOR_COMMIT,
                 os.path.join(args.out_dir, 'commit-history.png'),
                 'COMMITS (COUNT)', 'COUNT', 'GITHUB API')

    first = format_time(points[0]['ts'])
    last = format_time(points[-1]['ts'])
    print('stars=%d commits=%d points=%d window=%s..%s'
          % (stars, commits, len(points), first, last))
    return 0


if __name__ == '__main__':
    sys.exit(main())