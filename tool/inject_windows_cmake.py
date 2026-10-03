#!/usr/bin/env python3
"""给 Windows CMake 注入一个兼容宏，修复 permission_handler_windows 在新 MSVC 下的编译错误。

背景（CI 实证）：
- `permission_handler_windows` 使用旧的 `<experimental/coroutine>`（C++/WinRT）；
- 新版 MSVC（VS18 / STL1011）把它升级为**错误**，提示可定义
  `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` 抑制；
- `windows/` 目录由 CI 用 `flutter create` 现场生成，故在构建期
  **幂等注入**该宏（在 `project(...)` 之后、子目录之前定义，保证对所有插件生效）。

幂等：已注入则跳过；返回码 0 = 成功。
用法：
    python3 tool/inject_windows_cmake.py [--root .]
"""
import argparse
import os
import sys

MARKER = '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS'
CANDIDATES = ['windows/CMakeLists.txt']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', default='.')
    args = parser.parse_args()

    path = None
    for rel in CANDIDATES:
        candidate = os.path.join(args.root, rel)
        if os.path.exists(candidate):
            path = candidate
            break
    if path is None:
        print('[跳过] 未见 windows/CMakeLists.txt（非 Windows 构建？）')
        return 0

    text = open(path, encoding='utf-8').read()
    if MARKER in text:
        print('[已存在] %s 已注入兼容宏' % path)
        return 0

    lines = text.splitlines(keepends=True)
    insert_at = None
    for i, line in enumerate(lines):
        if line.lstrip().startswith('project('):
            insert_at = i + 1
            break
    if insert_at is None:
        print('[失败] %s 里找不到 project(...) 行' % path)
        return 1

    injection = (
        '# OGL: permission_handler_windows 使用旧的 <experimental/coroutine>，\n'
        '# 新版 MSVC 会将其判为错误；定义此宏以抑制（构建期注入）。\n'
        'add_compile_definitions(%s)\n' % MARKER
    )
    lines.insert(insert_at, injection)
    open(path, 'w', encoding='utf-8').write(''.join(lines))

    if MARKER not in open(path, encoding='utf-8').read():
        print('[失败] 注入后仍未看到宏')
        return 1
    print('[注入] %s → 已加入 %s' % (path, MARKER))
    print('[自检通过] Windows 兼容宏已就位')
    return 0


if __name__ == '__main__':
    sys.exit(main())