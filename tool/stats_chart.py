#!/usr/bin/env python3
"""抓取星标数与提交数，追加历史点，生成折线图 SVG。

用法：
    python3 tool/stats_chart.py --repo owner/name \
        --history stats/history.json --svg stats/star-history.svg

环境变量：
    GH_TOKEN  具备 repo 读取权限的令牌（Actions 中使用 secrets.GITHUB_TOKEN）。

设计要点：
- 历史文件为 JSON 数组，元素形如 {"t": "ISO8601", "stars": N, "commits": N}。
- 提交数用提交接口的 Link 头取末页编号，避免逐页遍历。
- 折线图两条线各自按极值缩放，避免量级差异导致其中一条贴底。
- 任一步失败以非 0 退出，工作流据此判红；不写入半成品文件。
"""

import argparse
import json
import os
import re
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone

API = "https://api.github.com"


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


def _scaled(values, lo, hi, height, pad):
    span = hi - lo
    if span <= 0:
        return [pad + height / 2.0 for _ in values]
    out = []
    for v in values:
        out.append(pad + (hi - v) / float(span) * height)
    return out


def _polyline(xs, ys, color):
    pts = " ".join("%.1f,%.1f" % (x, y) for x, y in zip(xs, ys))
    return ('<polyline fill="none" stroke="%s" stroke-width="2" '
            'stroke-linejoin="round" points="%s"/>' % (color, pts))


def render_svg(points, repo):
    width, height, pad = 760.0, 260.0, 36.0
    plot_w = width - pad * 2
    plot_h = height - pad * 2 - 18
    stars = [int(p.get("stars", 0)) for p in points]
    commits = [int(p.get("commits", 0)) for p in points]
    n = len(points)
    xs = [pad + (plot_w * i / (n - 1) if n > 1 else plot_w / 2.0) for i in range(n)]

    parts = []
    parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
                 'viewBox="0 0 %d %d">' % (width, height, width, height))
    parts.append('<rect width="100%%" height="100%%" fill="#ffffff"/>')
    parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" '
                 'stroke="#d0d7de"/>' % (pad, pad, plot_w, plot_h))
    for k in range(1, 4):
        y = pad + plot_h * k / 4.0
        parts.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" '
                     'stroke="#eaeef2"/>' % (pad, y, pad + plot_w, y))

    if n >= 1:
        ys = _scaled(stars, min(stars), max(stars), plot_h, pad)
        yc = _scaled(commits, min(commits), max(commits), plot_h, pad)
        if n >= 2:
            parts.append(_polyline(xs, ys, "#0969da"))
            parts.append(_polyline(xs, yc, "#2da44e"))
        else:
            parts.append('<circle cx="%.1f" cy="%.1f" r="3" fill="#0969da"/>' % (xs[0], ys[0]))
            parts.append('<circle cx="%.1f" cy="%.1f" r="3" fill="#2da44e"/>' % (xs[0], yc[0]))

    last = points[-1] if points else {}
    parts.append('<text x="%.1f" y="%.1f" font-family="monospace" font-size="13" '
                 'fill="#0969da">stars: %s</text>' % (pad, 20, last.get("stars", 0)))
    parts.append('<text x="%.1f" y="%.1f" font-family="monospace" font-size="13" '
                 'fill="#2da44e">commits: %s</text>' % (pad + 150, 20, last.get("commits", 0)))
    parts.append('<text x="%.1f" y="%.1f" font-family="monospace" font-size="11" '
                 'fill="#57606a">updated %s   points %d   %s</text>'
                 % (pad, height - 12, datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
                    n, repo))
    parts.append('</svg>')
    return "\n".join(parts) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--history", required=True)
    ap.add_argument("--svg", required=True)
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
    svg = render_svg(points, args.repo)
    os.makedirs(os.path.dirname(args.svg) or ".", exist_ok=True)
    with open(args.svg, "w", encoding="utf-8") as f:
        f.write(svg)
    print("stars=%d commits=%d points=%d" % (stars, commits, len(points)))
    return 0


if __name__ == "__main__":
    sys.exit(main())