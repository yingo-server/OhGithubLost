#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · i18n 抽取与校验工具（5.0 多语言工程的基础设施）。

## 它做什么
1. **抽取**：扫描 `lib/` 下所有 Dart 源码里的**中文字符串字面量**（跳过注释），
   按"文件 → 页面分片"映射，输出待翻译清单（JSON + CSV）。
2. **拆分**：按 `assets/i18n/<locale>/<page>.json` 的既有结构归类，
   并给出每个 page 的 key 计数（对照现有分片，指出缺哪些）。
3. **校验（--check）**：发现**新增的中文字面量**即有非零退出，供 CI 卡住回退；
   同时校验各语言分片的 key 集合是否与 zh 对齐（缺 key / 多 key）。

## 用法
    python3 tool/i18n_scan.py                    # 打印报告
    python3 tool/i18n_scan.py --json out.json    # 导出 JSON 清单
    python3 tool/i18n_scan.py --check            # CI 模式（有问题退出 1）
    python3 tool/i18n_scan.py --allowlist tool/i18n_allow.txt  # 允许的中文（如日志/注释）

## 设计取舍（与用户要求一致）
- 中文/英文**按语境人工翻译**，专有名词（GitHub / Release / Actions / PR / Token…）
  **不过度翻译**，描述不加额外语句 —— 因此工具只做"找出来、归类、对齐"，
  不自动机器翻译 zh/en；
- 其余语言由**机翻**产出，键集合以 zh 为基准（见 `--check`）。
"""
import argparse
import json
import os
import re
import sys

CJK = re.compile(r'[\u4e00-\u9fff]')
# 单/双引号字符串（含转义），以及 raw 字符串前缀。
STRING = re.compile(r"(?<![\w])(r?)('(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\")")
LINE_COMMENT = re.compile(r'//[^\n]*')

# 文件 → 页面分片 的映射（新增页面时在这里补一条）。
PAGE_BY_PREFIX = [
    ('lib/surface/app/', 'shell'),
    ('lib/surface/pages/settings_page.dart', 'settings'),
    ('lib/surface/pages/login_page.dart', 'login'),
    ('lib/surface/pages/onboarding_page.dart', 'onboarding'),
    ('lib/surface/pages/repo_page.dart', 'repo'),
    ('lib/surface/pages/', None),          # 其余页面：按文件名定
    ('lib/surface/widgets/', 'common'),
    ('lib/surface/util/', 'common'),
]


def page_of(rel):
    for prefix, page in PAGE_BY_PREFIX:
        if rel.startswith(prefix):
            if page is not None:
                return page
            base = os.path.basename(rel)[:-5]
            return base
    return 'common'


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return LINE_COMMENT.sub('', text)


def scan_file(path):
    """返回 [(line_no, text)]。"""
    found = []
    with open(path, encoding='utf-8') as handle:
        raw = handle.read()
    for index, line in enumerate(raw.split('\n'), start=1):
        code = strip_comments(line)
        for match in STRING.finditer(code):
            value = match.group(2)
            value = value[1:-1]
            if value.startswith("'") or value.startswith('"'):
                continue
            if CJK.search(value):
                found.append((index, value))
    return found


def collect(root):
    items = []
    for dirpath, _dirs, files in os.walk(root):
        for name in sorted(files):
            if not name.endswith('.dart'):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, os.path.dirname(root))
            for line, text in scan_file(full):
                items.append({
                    'file': rel,
                    'line': line,
                    'page': page_of(rel),
                    'text': text,
                })
    return items


def load_shard(locale_dir, page):
    path = os.path.join(locale_dir, '%s.json' % page)
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as handle:
        return json.load(handle)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lib', default='lib')
    parser.add_argument('--i18n', default='assets/i18n')
    parser.add_argument('--json', dest='json_out')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()

    items = collect(args.lib)
    by_page = {}
    for item in items:
        by_page.setdefault(item['page'], []).append(item)

    print('中文字面量（待本地化）：%d 处，分布在 %d 个页面分片'
          % (len(items), len(by_page)))
    for page in sorted(by_page):
        print('  %-14s %d 处' % (page, len(by_page[page])))

    # 与现有分片对齐：列出各语言缺哪些 page。
    if os.path.isdir(args.i18n):
        locales = sorted(
            d for d in os.listdir(args.i18n)
            if os.path.isdir(os.path.join(args.i18n, d)))
        print('\n语言目录：%s' % '、'.join(locales))
        zh_keys = {}
        for page in sorted(by_page):
            shard = load_shard(os.path.join(args.i18n, 'zh'), page)
            zh_keys[page] = set(shard.keys()) if shard else set()
        print('\n分片覆盖（zh 为基准）:')
        for page in sorted(by_page):
            have = len(zh_keys.get(page, ()))
            print('  %-14s zh key=%d / 源码中文=%d'
                  % (page, have, len(by_page[page])))
        missing = []
        for locale in locales:
            for page in sorted(by_page):
                shard = load_shard(os.path.join(args.i18n, locale), page)
                if shard is None:
                    missing.append('%s/%s 缺失' % (locale, page))
                    continue
                extra = set(shard.keys()) - zh_keys.get(page, set())
                if extra:
                    missing.append('%s/%s 多出 key：%s'
                                   % (locale, page, '、'.join(sorted(extra))))
        if missing:
            print('\n分片差异：')
            for row in missing[:40]:
                print('  ' + row)

    if args.json_out:
        with open(args.json_out, 'w', encoding='utf-8') as handle:
            json.dump(items, handle, ensure_ascii=False, indent=2)
        print('\n已导出：%s' % args.json_out)

    if args.check and items:
        print('\n[check] 仍有 %d 处中文字面量未本地化'
              % len(items), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())