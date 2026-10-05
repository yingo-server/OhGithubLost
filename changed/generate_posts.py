#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把根目录 release_notes/v<tag>.md 生成为 Jekyll _posts（Pages 用）。

- 从文件名解析版本号与发布日期（读取线上 release 的 created_at 更准，
  这里用 release_notes/ 文件名 + 简单映射）。
- 产出 changed/_posts/YYYY-MM-DD-v<tag>.md（front matter + 正文）。

用法：
    python3 changed/generate_posts.py [--release-notes-dir 根目录/release_notes]
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys
import urllib.request
import json

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))

# 版本 → 发布日期（取线上 Release created_at；本地兜底表）
FALLBACK_DATES = {
    'v0.1.0': '2026-10-01',
    'v0.2.0-beta': '2026-10-01',
    'v1.0.0': '2026-10-01',
    'v1.1.0': '2026-10-01',
    'v1.4': '2026-10-02',
    'v2.0.0': '2026-10-02',
    'v2.2.0': '2026-10-02',
    'v3.0.0': '2026-10-03',
    'v3.1.0': '2026-10-03',
    'v3.2.0': '2026-10-03',
    'v4.0.0': '2026-10-03',
    'v4.1.0': '2026-10-03',
    'v4.2.0': '2026-10-03',
    'v4.3.0': '2026-10-03',
    'v4.4.0': '2026-10-03',
    'v4.5.0': '2026-10-03',
    'v4.6.0': '2026-10-03',
    'v4.7.0': '2026-10-03',
    'v4.8.0': '2026-10-03',
    'v4.9.0': '2026-10-04',
    'v5.0.0-beta': '2026-10-04',
    'v5.1.0': '2026-10-04',
    'v5.2.0': '2026-10-04',
    'v5.3.0': '2026-10-04',
    'v5.6.0': '2026-10-04',
    'v6.0.0': '2026-10-05',
}


def fetch_dates() -> dict:
    """从线上 Release 拿 created_at（可选；失败则用兜底表）。"""
    try:
        token_path = os.path.join(HERE, '..', '..', '_setup', '.gh_token')
        token = open(token_path, encoding='utf-8').read().strip()
        req = urllib.request.Request(
            'https://api.github.com/repos/yingo-server/OhGithubLost/releases?per_page=50',
            headers={'Authorization': 'Bearer ' + token,
                     'Accept': 'application/vnd.github+json'})
        with urllib.request.urlopen(req, timeout=30) as resp:
            releases = json.loads(resp.read().decode('utf-8'))
        return {r['tag_name']: r['published_at'][:10] for r in releases}
    except Exception as exc:  # noqa: BLE001
        print('[warn] 线上日期拉取失败，用兜底表：%s' % exc)
        return {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--release-notes-dir',
                    default=os.path.join(REPO, 'release_notes'))
    ap.add_argument('--created-at', action='store_true',
                    help='优先用线上 Release created_at')
    args = ap.parse_args()

    dates = fetch_dates() if args.created_at else {}
    posts_dir = os.path.join(HERE, '_posts')
    os.makedirs(posts_dir, exist_ok=True)

    written = 0
    for path in sorted(glob.glob(os.path.join(args.release_notes_dir, 'v*.md'))):
        tag = os.path.basename(path)[:-3]          # v5.6.0
        body = open(path, encoding='utf-8').read()
        date = dates.get(tag) or FALLBACK_DATES.get(tag)
        if not date:
            print('[skip] 无日期：%s' % tag)
            continue
        # 标题取正文第一行（如 "## OhGithubLost 5.6.0 · 正式版"）
        title = body.splitlines()[0].lstrip('# ').strip() if body.strip() else tag
        front = (
            '---\n'
            'layout: post\n'
            'title: "%s"\n'
            'date: %s\n'
            'categories: [release]\n'
            'version: %s\n'
            '---\n\n' % (title.replace('"', '\\"'), date, tag)
        )
        out = os.path.join(posts_dir, '%s-%s.md' % (date, tag))
        with open(out, 'w', encoding='utf-8') as handle:
            handle.write(front + body)
        print('[ok]', os.path.relpath(out, REPO))
        written += 1

    print('生成 %d 篇博客' % written)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
