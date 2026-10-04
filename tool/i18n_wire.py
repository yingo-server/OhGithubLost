#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · i18n 接线器：把页面 Dart 源码里的中文字面量替换为 `t(page, key)`。

流程
----
1. 读 `assets/i18n/zh/<page>.json`，建立**反查表**：文案 → 键。
2. 扫描目标 Dart 文件里的字符串字面量（跳过注释），规范化后查表：
   - 纯文案     `'已创建'`        → `_t('created')`
   - 带插值     `'已复制${x}'`     → `_t('copied', {'label': x})`
   （插值按**位置**绑定到分片里的占位符名，顺序一致才替换。）
3. 自动补齐 `import '../i18n/og_l_i18n.dart';` 与文件级 `_t` 助手。
4. **自动剥掉失效的 `const`**：若某 `const` 构造/列表内部出现 `_t(`，
   则去掉该 `const`（这是 analyze 报错的主要来源）。
5. 未匹配到的中文字面量（日志、标签等）原样保留并报告。

用法
----
    python3 tool/i18n_wire.py --dry-run      # 只报告
    python3 tool/i18n_wire.py                # 写入
    python3 tool/i18n_wire.py --file lib/surface/pages/pull_page.dart
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, 'lib')
ZH_DIR = os.path.join(ROOT, 'assets', 'i18n', 'zh')
I18N_REL = 'i18n/og_l_i18n.dart'

MARK = '\u0001'
CJK = re.compile(r'[\u4e00-\u9fff]')
# 单/双引号字符串（不跨行），允许转义与 raw 前缀。
STRING = re.compile(r"(?<![\w])(r?)('(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\")")
INTERP = re.compile(r'\$\{([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)')
PLACEHOLDER = re.compile(r'\{([A-Za-z0-9_]+)\}')

PAGE_BY_PREFIX = [
    ('lib/surface/app/', 'shell'),
    ('lib/surface/pages/settings_page.dart', 'settings'),
    ('lib/surface/pages/login_page.dart', 'login'),
    ('lib/surface/pages/onboarding_page.dart', 'onboarding'),
    ('lib/surface/pages/repo_page.dart', 'repo'),
    ('lib/surface/pages/', None),
    ('lib/surface/widgets/', 'common'),
    ('lib/surface/util/', 'common'),
    ('lib/surface/', 'common'),
]


def page_of(rel):
    for prefix, page in PAGE_BY_PREFIX:
        if rel.startswith(prefix):
            if page is not None:
                return page
            return os.path.basename(rel)[:-5]
    return None


def strip_comments(text):
    """把注释替换成等长空格，保留偏移。"""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                out[i] = ' '
                i += 1
        elif ch == '/' and i + 1 < n and text[i + 1] == '*':
            out[i] = out[i + 1] = ' '
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                if text[i] != '\n':
                    out[i] = ' '
                i += 1
            if i + 1 < n:
                out[i] = out[i + 1] = ' '
                i += 2
        else:
            i += 1
    return ''.join(out)


def unescape(text):
    """还原 Dart 字符串转义，便于与 JSON 里的真实字符比较。"""
    return (text.replace('\\n', '\n').replace('\\t', '\t')
            .replace('\\r', '\r').replace("\\'", "'").replace('\\"', '"')
            .replace('\\\\', '\\'))


def canonical(text):
    """占位符/插值统一成标记，反转义、去空白，便于反查。"""
    text = unescape(text)
    text = INTERP.sub(MARK, text)
    text = PLACEHOLDER.sub(MARK, text)
    return re.sub(r'\s+', '', text)


def load_reverse(page):
    path = os.path.join(ZH_DIR, '%s.json' % page)
    if not os.path.exists(path):
        return {}, {}
    with open(path, encoding='utf-8') as handle:
        data = json.load(handle)
    reverse, names = {}, {}
    for key in sorted(data):
        value = data[key]
        reverse.setdefault(canonical(value), (key, value))
        names[key] = PLACEHOLDER.findall(value)
    return reverse, names


def const_spans(text):
    """返回所有需要删除的 `const ` 起止偏移（其构造体内部含 _t( 调用）。"""
    spans = []
    for match in re.finditer(r'\bconst\b', text):
        start = match.end()
        i = start
        # 声明形式 `const X = ...` 不是构造调用，跳过。
        probe = re.match(r'\s*[A-Za-z_][A-Za-z0-9_]*\s*=', text[i:])
        if probe:
            continue
        # 跳过空白
        while i < len(text) and text[i].isspace():
            i += 1
        # 跳过构造函数 / 类型名（如 `const Text(` 的 Text）
        m = re.match(r'[A-Za-z_][A-Za-z0-9_.]*', text[i:])
        if m:
            i += m.end()
        # 跳过空白与泛型 <...>
        while i < len(text) and text[i].isspace():
            i += 1
        if i < len(text) and text[i] == '<':
            depth = 0
            while i < len(text):
                if text[i] == '<':
                    depth += 1
                elif text[i] == '>':
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            while i < len(text) and text[i].isspace():
                i += 1
        if i >= len(text) or text[i] not in '([{':
            continue
        # 平衡扫描
        stack = []
        j = i
        pairs = {'(': ')', '[': ']', '{': '}'}
        while j < len(text):
            if text[j] in pairs:
                stack.append(pairs[text[j]])
            elif stack and text[j] == stack[-1]:
                stack.pop()
                if not stack:
                    break
            elif text[j] in ')]}':
                break
            j += 1
        body = text[i:j + 1]
        if '_t(' in body or 'OgLI18n.instance.t(' in body:
            spans.append((match.start(), match.end()))
    return spans


def wire_file(rel, apply_changes, stats):
    page = page_of(rel)
    if page is None or rel.startswith('lib/surface/i18n/'):
        return None
    reverse, names = load_reverse(page)
    if not reverse:
        return None
    path = os.path.join(ROOT, rel)
    text = open(path, encoding='utf-8').read()
    masked = strip_comments(text)

    edits = []
    unmatched = []
    for match in STRING.finditer(masked):
        raw = match.group(0)
        content = match.group(2)[1:-1]
        if not CJK.search(content) and MARK not in canonical(content):
            continue
        canon = canonical(content)
        hit = reverse.get(canon)
        if not hit:
            if CJK.search(content):
                unmatched.append(content)
            continue
        key, value = hit
        exprs = [g1 if g1 is not None else g2 for g1, g2 in INTERP.findall(content)]
        ph_names = names[key]
        if len(exprs) != len(ph_names):
            unmatched.append(content)
            continue
        if exprs:
            args = ', '.join("'%s': %s" % (name, expr)
                             for name, expr in zip(ph_names, exprs))
            call = "_t('%s', <String, String>{%s})" % (key, args)
        else:
            call = "_t('%s')" % key
        edits.append((match.start(), match.end(), call))

    if not edits:
        return {'rel': rel, 'page': page, 'applied': 0, 'unmatched': unmatched}

    new = text
    for start, end, call in sorted(edits, reverse=True):
        new = new[:start] + call + new[end:]

    # 补 import
    if "_t('" in new and 'og_l_i18n.dart' not in new:
        depth = rel.count('/') - 1  # lib/ 之下的层级
        # 目标文件目录 → i18n 目录的相对路径
        target_dir = os.path.dirname(rel)
        import_path = os.path.relpath(os.path.join('lib', 'surface', I18N_REL),
                                      target_dir).replace('\\', '/')
        # 插到最后一个 import 之后
        imports = list(re.finditer(r'^import .*?;$', new, re.M))
        if imports:
            pos = imports[-1].end()
            new = new[:pos] + "\nimport '%s';" % import_path + new[pos:]

    # 补 _t 助手
    if "_t('" in new and 'String _t(' not in new:
        imports = list(re.finditer(r'^import .*?;$', new, re.M))
        pos = imports[-1].end() if imports else 0
        helper = ("\n\n/// 取 `%s` 分片文案。\n"
                  "String _t(String key, [Map<String, String>? args]) =>\n"
                  "    OgLI18n.instance.t('%s', key, args: args);" % (page, page))
        new = new[:pos] + helper + new[pos:]

    # 剥掉失效 const
    if "_t('" in new:
        for start, end in sorted(const_spans(new), reverse=True):
            new = new[:start] + new[end:]

    if apply_changes and new != text:
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(new)

    stats['total'] += len(edits)
    return {'rel': rel, 'page': page, 'applied': len(edits),
            'unmatched': unmatched}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--file')
    parser.add_argument('--only', help='只处理这些页面（逗号分隔）')
    parser.add_argument('--fix-const', action='store_true',
                        help='只做一件事：剥掉内部含有 _t( 的 const')
    args = parser.parse_args()

    only = set(args.only.split(',')) if args.only else None
    files = []
    if args.file:
        files = [args.file]
    else:
        for dirpath, _, filenames in os.walk(os.path.join(ROOT, 'lib', 'surface')):
            for name in filenames:
                if name.endswith('.dart'):
                    files.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    files.sort()

    stats = {'total': 0}
    rows = []

    if getattr(args, 'fix_const', False):
        fixed = 0
        for rel in files:
            path = os.path.join(ROOT, rel)
            text = open(path, encoding='utf-8').read()
            spans = sorted(const_spans(text), reverse=True)
            if not spans:
                continue
            for start, end in spans:
                text = text[:start] + text[end:]
            fixed += len(spans)
            if not args.dry_run:
                with open(path, 'w', encoding='utf-8') as handle:
                    handle.write(text)
            print('%-52s 去掉 %d 个 const' % (rel, len(spans)))
        print('\n合计去掉 %d 个 const（%s）'
              % (fixed, 'dry-run' if args.dry_run else '已写入'))
        return 0

    for rel in files:
        page = page_of(rel)
        if only and page not in only:
            continue
        result = wire_file(rel, not args.dry_run, stats)
        if result:
            rows.append(result)

    print('%-52s %-22s %6s %s' % ('文件', '页面', '替换', '未匹配'))
    for row in rows:
        print('%-52s %-22s %6d %d'
              % (row['rel'], row['page'], row['applied'], len(row['unmatched'])))
    print('\n合计替换 %d 处（%s）'
          % (stats['total'], 'dry-run' if args.dry_run else '已写入'))
    return 0


if __name__ == '__main__':
    sys.exit(main())