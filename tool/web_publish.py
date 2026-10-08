#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把构建好的 Web 产物按版本发布到 `app/`，并重写 `app/index.html`。

## 目录约定
```
app/
  index.html          ← **入口**：一个 iframe 包裹当前版本（始终指向最新）
  versions.json       ← 已发布版本清单（新版本在前）
  v650/               ← 某个版本的完整 Web 产物
    index.html …
  v640/
    …
```

## 为什么用 iframe 而不是把产物直接铺在 `app/` 根下
版本目录并存时，根下只能放一份。用 iframe 包一层，好处是：
- **旧版本继续可访问**（`app/v640/…`），便于对比与回退；
- 入口地址 `app/` 永远不变，外部链接不需要跟着版本改；
- 版本切换只是改 iframe 的 `src`。

## 用法
    python3 tool/web_publish.py <构建产物目录> <版本号>
例：  python3 tool/web_publish.py build/web 6.5.0
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def version_dir_name(version: str) -> str:
    """版本号 → 目录名：`6.5.0` → `v650`（去掉点，前缀 v）。

    用户要求的形式是 `v620` 这样的紧凑写法。
    """
    digits = re.sub(r'[^0-9]', '', version)
    if not digits:
        raise ValueError('版本号里没有数字：%r' % version)
    return 'v' + digits


WRAPPER = """<!DOCTYPE html>
<!--
  OGL Web · 入口页（**自动生成，请勿手改**）。

  由 `tool/web_publish.py` 写出。它把当前版本的应用包在一个 iframe 里，
  这样根地址始终不变，而各版本目录可以并存。
-->
<html lang="zh">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <title>OhGithubLost · Web</title>
  <meta name="theme-color" content="#171A21">
  <style>
    html, body { margin: 0; padding: 0; height: 100%; background: #171A21; }
    #app { display: block; width: 100vw; height: 100vh; border: 0; }
    /* 版本切换条：默认收起，点击右上角展开 */
    #bar {
      position: fixed; right: 8px; bottom: 8px; z-index: 9;
      font: 12px/1.6 system-ui, sans-serif;
    }
    #bar > button {
      background: #2F3441; color: #E6EDF3; border: 1px solid #454B5A;
      border-radius: 6px; padding: 4px 10px; cursor: pointer;
    }
    #list {
      display: none; margin-bottom: 6px; background: #1E222B;
      border: 1px solid #454B5A; border-radius: 6px; padding: 6px 0;
      max-height: 40vh; overflow: auto; min-width: 120px;
    }
    #list a { display: block; padding: 3px 12px; color: #E6EDF3;
              text-decoration: none; white-space: nowrap; }
    #list a:hover { background: #2F3441; }
    #list a.cur { color: #FFC93C; }
  </style>
</head>
<body>
  <iframe id="app" src="__CURRENT__/" title="OhGithubLost"></iframe>
  <div id="bar">
    <div id="list"></div>
    <button type="button" onclick="var l=document.getElementById('list');l.style.display=l.style.display==='block'?'none':'block'">版本</button>
  </div>
  <script>
    // 版本清单来自 versions.json；切换只是换 iframe 的 src，不刷新外层。
    fetch('versions.json').then(r => r.ok ? r.json() : []).then(list => {
      const box = document.getElementById('list');
      const cur = '__CURRENT__';
      (list || []).forEach(v => {
        const a = document.createElement('a');
        a.textContent = v.version;
        a.href = v.dir + '/';
        if (v.dir === cur) a.className = 'cur';
        a.onclick = e => { e.preventDefault(); document.getElementById('app').src = v.dir + '/'; return false; };
        box.appendChild(a);
      });
    }).catch(() => {});
  </script>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser(description='把 Web 产物按版本发布到 app/')
    ap.add_argument('build_dir', help='构建产物目录（如 build/web）')
    ap.add_argument('version', help='版本号（如 6.5.0）')
    ap.add_argument('--app-dir', default=os.path.join(ROOT, 'app'))
    args = ap.parse_args()

    if not os.path.isdir(args.build_dir):
        sys.stderr.write('构建产物目录不存在：%s\n' % args.build_dir)
        return 1
    if not os.path.isfile(os.path.join(args.build_dir, 'index.html')):
        sys.stderr.write('%s 里没有 index.html —— 看起来不是 Flutter Web 产物\n'
                         % args.build_dir)
        return 1

    app_dir = args.app_dir
    dir_name = version_dir_name(args.version)
    target = os.path.join(app_dir, dir_name)
    os.makedirs(app_dir, exist_ok=True)
    # 同版本重发：先清掉旧的，避免残留上一轮的文件。
    if os.path.isdir(target):
        shutil.rmtree(target)
    shutil.copytree(args.build_dir, target)
    print('已发布 %s → %s' % (args.version, os.path.relpath(target, ROOT)))

    # 版本清单（新版本在前；同版本去重）
    manifest_path = os.path.join(app_dir, 'versions.json')
    entries = []
    if os.path.isfile(manifest_path):
        try:
            with open(manifest_path, encoding='utf-8') as fh:
                entries = [e for e in json.load(fh)
                           if isinstance(e, dict) and e.get('dir') != dir_name]
        except Exception:
            entries = []
    entries.insert(0, {'version': args.version, 'dir': dir_name})
    with open(manifest_path, 'w', encoding='utf-8') as fh:
        json.dump(entries, fh, ensure_ascii=False, indent=2)
        fh.write('\n')

    # 入口页：指向刚发布的版本
    with open(os.path.join(app_dir, 'index.html'), 'w', encoding='utf-8') as fh:
        fh.write(WRAPPER.replace('__CURRENT__', dir_name))
    print('已重写 app/index.html → iframe 指向 %s/' % dir_name)
    print('已更新 app/versions.json（共 %d 个版本）' % len(entries))
    return 0


if __name__ == '__main__':
    sys.exit(main())
