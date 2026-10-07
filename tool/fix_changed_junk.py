#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""清理 changed/ 下被误写入的畸形文件名（例如把正文当成文件名写进去的条目）。

## 这个脚本本身出过一次事故（务必保留说明）
早期实现对 `changed/` 采用「**不在白名单就删**」的策略，白名单里只有
`_config.yml` / `_posts` / `index.md` / `generate_posts.py` —— 而 `Gemfile`
是后来才加的，于是**跑一次就把这个正经文件删了**（它是 Jekyll 构建锁版本的
关键文件，删掉会让日志站点的构建随镜像漂移）。

「白名单之外的都算垃圾」是个只会越用越危险的策略：仓库每加一个文件，都要
记得回来补白名单，忘了就是静默删除。现在改成**双重条件**——
既不在白名单里、**又**名字确实长得像被误写入的正文，才会删；
其余一律只报告、不动手。
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, 'changed')

# 目录与已知的正经文件：一律保留。
KEEP = {
    '_config.yml', 'Gemfile', 'Gemfile.lock', 'index.md',
    'generate_posts.py', 'CNAME', 'README.md', '.gitignore',
}

# 「被误写入的正文」的判据：文件名里出现了正文特征。
JUNK_MARKERS = ('\n', '\r', ' # ', '## ', '<!--', ' --- ')


def looks_like_junk(name: str) -> bool:
    """名字是否确实像「正文被当成文件名」。"""
    if any(marker in name for marker in JUNK_MARKERS):
        return True
    if len(name) > 120:          # 正经文件名不会这么长
        return True
    if name.count(' ') >= 3:     # 连续多个空格 = 一段话
        return True
    return False


def main() -> int:
    removed, kept_back = [], []
    for name in sorted(os.listdir(TARGET)):
        path = os.path.join(TARGET, name)
        if name in KEEP or os.path.isdir(path):
            continue
        if not looks_like_junk(name):
            kept_back.append(name)
            continue
        removed.append(name)
        os.remove(path)
    if kept_back:
        print('保留（不认识但不是垃圾，请人工确认）：%s' % kept_back)
    print('removed: %s' % removed)
    return 0


if __name__ == '__main__':
    sys.exit(main())
