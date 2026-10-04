#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 动效分级审计（CI 门禁）。

## 它守什么
用户要求：动画必须**严格按档位分级**（1 最保守 → 3 拉满），
"降档 = 降质量"而不是"各处自己写死时长/效果"。

因此本工具在 `lib/surface/**` 里禁止：

1. **硬编码动画时长**（`Duration(milliseconds: …)`）——时长只能来自
   `OgLOAnimQuality` 的档位表（`app/motion.dart`），经 `OgLAnim` 读取；
2. **硬编码缩放 / 模糊**（`ScaleTransition(` / `AnimatedScale(` /
   `BackdropFilter(` / `ImageFilter.blur`）——缩放与模糊在低档位必须关闭，
   只允许出现在档位表与工具箱里；
3. **匀速动画**（`Curves.linear`）——匀速运动"机械 / 死板"、不符合直觉；
   动画一律走**自然减速**（ease-out 阶梯），曲线只能来自档位表
   （`motion.dart` 的 `curve` / `largeCurve`）。档位 `0`（无动画）中的
   `Curves.linear` 因位于白名单文件里而不被检查。

允许名单（白名单文件 / 行内例外）写在下方的 [ALLOW_FILES] 与 [ALLOW_LINE_HINTS]：
- `app/motion.dart`、`app/animations.dart` 是档位表与工具箱本身；
- 非动画的等待时长（节流、缓存 TTL、草稿防抖、双击退出窗口）用行内提示词豁免
  （`Timer(` / `throttle` / `ttl` / `debounce` / `exitWindow` / `Cache`）。

## 用法
    python3 tool/motion_audit.py            # 打印报告
    python3 tool/motion_audit.py --fatal    # CI：有违规即退出码 1
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SURFACE = os.path.join(ROOT, 'lib', 'surface')

# 档位表 / 工具箱本身（唯一允许出现原始时长与缩放的地方）
ALLOW_FILES = {
    'lib/surface/app/motion.dart',
    'lib/surface/app/animations.dart',
}

# 行内例外：这些是"等待/节流"，不是动画
ALLOW_LINE_HINTS = (
    'Timer(',
    'throttle',
    'ttl',
    'debounce',
    'exitWindow',
    'Cache',
    'cache',
)

PATTERNS = [
    ('硬编码动画时长', re.compile(r'Duration\(\s*milliseconds:\s*\d')),
    ('硬编码缩放过渡', re.compile(r'\b(?:ScaleTransition|AnimatedScale)\(')),
    ('硬编码模糊', re.compile(r'(?:BackdropFilter|ImageFilter\.blur)\(')),
    ('匀速动画（死板）', re.compile(r'\bCurves\.linear\b')),
]


def audit():
    violations = []
    scanned = 0
    for dirpath, _dirs, files in os.walk(SURFACE):
        for name in sorted(files):
            if not name.endswith('.dart'):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, ROOT)
            scanned += 1
            if rel in ALLOW_FILES:
                continue
            with open(full, encoding='utf-8') as handle:
                for index, line in enumerate(handle, start=1):
                    stripped = line.strip()
                    if stripped.startswith('//') or stripped.startswith('///'):
                        continue
                    if any(hint in line for hint in ALLOW_LINE_HINTS):
                        continue
                    for label, pattern in PATTERNS:
                        if pattern.search(line):
                            violations.append((rel, index, label, stripped[:100]))
    return scanned, violations


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fatal', action='store_true',
                        help='有违规时退出码 1（供 CI 使用）')
    args = parser.parse_args()

    scanned, violations = audit()
    print('动效分级审计：扫描 %d 个文件（白名单 %d 个）'
          % (scanned, len(ALLOW_FILES)))
    if not violations:
        print('违规：0 处 —— 所有动画都走档位质量表 ✅')
        return 0
    print('违规：%d 处' % len(violations))
    for rel, line, label, text in violations:
        print('  %s:%d [%s] %s' % (rel, line, label, text))
    print('\n修法：时长 / 位移 / 缩放一律经 `OgLAnim`（读 `OgLOAnimQuality` 档位表）；'
          '确属等待（非动画）请加行内提示词或登记白名单。')
    return 1 if args.fatal else 0


if __name__ == '__main__':
    sys.exit(main())