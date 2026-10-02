#!/usr/bin/env python3
"""抓取星标数与提交数，追加历史点，生成两张折线图（PNG）。

用法：
    python3 tool/stats_chart.py --repo owner/name --history stats/history.json \
        --out-dir stats

产出：
    <out-dir>/star-history.png    星标折线图
    <out-dir>/commit-history.png  提交折线图

环境变量：
    GH_TOKEN  具备读取权限的令牌（Actions 中使用 secrets.GITHUB_TOKEN）。

实现说明：
- 选 PNG 而非 SVG：GitHub 对 README 内 SVG 的代理支持不稳定，PNG 稳定显示。
- 不依赖第三方绘图库：用 zlib 与 struct 直接写 PNG，Actions 中零安装运行。
- 图形不绘制文字（无需字体）：颜色含义写在 README 图注中。
- 提交数用提交接口的 Link 头取末页编号。
- 任一步失败以非 0 退出，工作流据此判红。
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

API = "https://api.github.com"

WIDTH = 760
HEIGHT = 260
PAD = 36
GRID = (234, 238, 242)
BORDER = (208, 215, 222)
BG = (255, 255, 255)


def _request(path, token):
    req = urllib.request.Request(API + path)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "ogl-stats")
    return urllib.request.urlopen(req, timeout=60)


def fetch_stars(repo, token):
    with _request("/repos/" + repo, token) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return int(data.get("stargazers_count", 0))


def fetch_commits(repo, token):
    """提交数：per_page=1 时，Link 头 rel=last 的 page 即总数。"""
    with _request("/repos/%s/commits?per_page=1" % repo, token) as resp:
        link = resp.headers.get("Link", "")
        body = json.loads(resp.read().decode("utf-8"))
    if link:
        m = re.search(r'[?&]page=(\d+)>;\s*rel="last"', link)
        if m:
            return int(m.group(1))
    return len(body) if isinstance(body, list) else 0


def load_history(path):
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception as exc:
        print("history 读取失败，按空历史处理：%s" % exc, file=sys.stderr)
        return []


def write_history(path, points):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(points, f, ensure_ascii=False, indent=2)
        f.write("\n")


# ───────────────────────── PNG 绘制 ─────────────────────────

def _canvas(width, height, color):
    row = bytes(color) * width
    return [bytearray(row) for _ in range(height)]


def _rect(rows, x0, y0, x1, y1, color):
    h = len(rows)
    w = len(rows[0]) // 3
    for y in range(max(0, y0), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            rows[y][3 * x:3 * x + 3] = bytes(color)


def _line(rows, x0, y0, x1, y1, color, thick=2):
    steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(steps):
        t = i / float(steps)
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        _rect(rows, x, y, x + thick, y + thick, color)


def _write_png(path, rows):
    width = len(rows[0]) // 3
    height = len(rows)
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(blob)


def _scaled(values, plot_h):
    lo, hi = min(values), max(values)
    span = hi - lo

    def fx(v):
        if span <= 0:
            return PAD + plot_h / 2.0
        return PAD + (hi - v) / float(span) * plot_h
    return [fx(v) for v in values]


def render_series(points, key, color, path):
    """按一个指标绘制折线图并写出 PNG。"""
    rows = _canvas(WIDTH, HEIGHT, BG)
    plot_w = WIDTH - PAD * 2
    plot_h = HEIGHT - PAD * 2 - 18
    # 边框
    _rect(rows, PAD, PAD, PAD + plot_w, PAD + 1, BORDER)
    _rect(rows, PAD, PAD + plot_h - 1, PAD + plot_w, PAD + plot_h, BORDER)
    _rect(rows, PAD, PAD, PAD + 1, PAD + plot_h, BORDER)
    _rect(rows, PAD + plot_w - 1, PAD, PAD + plot_w, PAD + plot_h, BORDER)
    # 网格
    for k in range(1, 4):
        y = int(PAD + plot_h * k / 4.0)
        _rect(rows, PAD + 1, y, PAD + plot_w - 1, y + 1, GRID)

    values = [int(p.get(key, 0)) for p in points]
    n = len(values)
    if n >= 1:
        ys = _scaled(values, plot_h)
        xs = [int(PAD + (plot_w - 1) * (i / (n - 1) if n > 1 else 0.5)) for i in range(n)]
        if n >= 2:
            for i in range(n - 1):
                _line(rows, xs[i], int(ys[i]), xs[i + 1], int(ys[i + 1]), color)
        else:
            _rect(rows, xs[0] - 3, int(ys[0]) - 3, xs[0] + 3, int(ys[0]) + 3, color)
    _write_png(path, rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--history", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--max-points", type=int, default=500)
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    if not token:
        print("缺少 GH_TOKEN / GITHUB_TOKEN", file=sys.stderr)
        return 2

    try:
        stars = fetch_stars(args.repo, token)
        commits = fetch_commits(args.repo, token)
    except urllib.error.HTTPError as exc:
        print("接口请求失败：HTTP %s" % exc.code, file=sys.stderr)
        return 3

    points = load_history(args.history)
    points.append({
        "t": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "stars": stars,
        "commits": commits,
    })
    if len(points) > args.max_points:
        points = points[-args.max_points:]

    write_history(args.history, points)
    render_series(points, "stars", (9, 105, 218),
                  os.path.join(args.out_dir, "star-history.png"))
    render_series(points, "commits", (45, 164, 78),
                  os.path.join(args.out_dir, "commit-history.png"))
    print("stars=%d commits=%d points=%d" % (stars, commits, len(points)))
    return 0


if __name__ == "__main__":
    sys.exit(main())