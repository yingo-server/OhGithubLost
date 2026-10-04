#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 桌面原生壳注入（图标与窗口标题，**幂等 + 自检**）。

## 为什么必须动原生壳
窗口标题与任务栏图标**不是 Flutter 绘制的**，而是操作系统读取的：
- Windows：`main.cpp` 里 `window.Create(...)` 的标题、`Runner.rc` 的资源与版本信息；
- Linux：`my_application.cc` 里 `gtk_window_set_title` / `gtk_header_bar_set_title`。
Flutter 层设置得再对，也改不了这两处 —— 所以必须在这里改。

## 图标（桌面用 2048 级母版）
唯一事实来源是 `assets/icon/ogl_icon.svg`；本工具调用
`tool/desktop_icon.py`（**零第三方依赖**的光栅化）现场生成：
- Windows：`windows/runner/resources/app_icon.ico` —— **只保留 256 单帧**
  （按约定，Win10/11 会自行下采样到 16/32/48）；
- Linux：`linux/runner/resources/ogl_icon_2048.png` —— **2048×2048**，
  打包时进 `hicolor/256x256/apps`（deb/rpm）与 AppImage 的 `.DirIcon`。

## 桌面窗口装饰
桌面端**不使用系统默认标题栏**（Flutter 侧自绘一套符合 App 风格的），
但原生标题仍然要写对：任务栏 / Alt-Tab / 任务管理器读的是**原生标题**，
不是 Flutter 画出来的那一条。
"""

from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import desktop_icon  # noqa: E402  （同目录工具模块）

APP_NAME = 'OhGithubLost'
SVG = os.path.join('assets', 'icon', 'ogl_icon.svg')
WINDOWS_ICO_SIZE = 256
LINUX_PNG_SIZE = 2048


def _read(path: str) -> str:
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def _write(path: str, text: str) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write(text)


def emit_windows_ico(target: str) -> None:
    """生成 Windows 单帧 256 ICO。"""
    os.makedirs(os.path.dirname(target), exist_ok=True)
    rgba = desktop_icon.render_rgba(SVG, WINDOWS_ICO_SIZE)
    png = desktop_icon.encode_png(rgba, WINDOWS_ICO_SIZE)
    with open(target, 'wb') as handle:
        handle.write(desktop_icon.encode_ico(png, WINDOWS_ICO_SIZE))
    print('[图标] Windows ICO %dx%d → %s' % (WINDOWS_ICO_SIZE, WINDOWS_ICO_SIZE, target))


def emit_linux_png(target: str) -> None:
    """生成 Linux 2048 PNG 母版。"""
    os.makedirs(os.path.dirname(target), exist_ok=True)
    rgba = desktop_icon.render_rgba(SVG, LINUX_PNG_SIZE)
    with open(target, 'wb') as handle:
        handle.write(desktop_icon.encode_png(rgba, LINUX_PNG_SIZE))
    print('[图标] Linux PNG %dx%d → %s' % (LINUX_PNG_SIZE, LINUX_PNG_SIZE, target))


def inject_windows() -> None:
    """Windows：窗口标题 + 版本信息 + 图标。"""
    main = os.path.join('windows', 'runner', 'main.cpp')
    if os.path.exists(main):
        text = _read(main)
        updated = re.sub(
            r'(window\.Create\(L")[^"]*(")',
            lambda m: m.group(1) + APP_NAME + m.group(2),
            text,
        )
        updated = re.sub(
            r'(window\.Create\(")[^"]*(")',
            lambda m: m.group(1) + APP_NAME + m.group(2),
            updated,
        )
        if updated != text:
            _write(main, updated)
            print('[注入] %s window.Create 标题 → %s' % (main, APP_NAME))
        if APP_NAME not in updated:
            print('[失败] %s 里找不到目标标题，注入无效' % main)
            raise SystemExit(1)

    emit_windows_ico(os.path.join('windows', 'runner', 'resources', 'app_icon.ico'))

    rc = os.path.join('windows', 'runner', 'Runner.rc')
    if os.path.exists(rc):
        text = _read(rc)
        for field, value in (
            ('ProductName', APP_NAME),
            ('FileDescription', APP_NAME),
            ('InternalName', APP_NAME),
            ('OriginalFilename', APP_NAME + '.exe'),
        ):
            text = re.sub(
                r'(VALUE\s+"%s",\s*")[^"]*(")' % field,
                lambda m, v=value: m.group(1) + v + m.group(2),
                text,
            )
        _write(rc, text)
        print('[注入] Runner.rc 版本信息 → %s' % APP_NAME)


def inject_linux() -> None:
    """Linux：窗口标题 + 图标母版。"""
    src = os.path.join('linux', 'runner', 'my_application.cc')
    if os.path.exists(src):
        text = _read(src)
        text = re.sub(
            r'(gtk_header_bar_set_title\(header_bar,\s*")[^"]*(")',
            lambda m: m.group(1) + APP_NAME + m.group(2),
            text,
        )
        text = re.sub(
            r'(gtk_window_set_title\(window,\s*")[^"]*(")',
            lambda m: m.group(1) + APP_NAME + m.group(2),
            text,
        )
        _write(src, text)
        print('[注入] %s 窗口标题 → %s' % (src, APP_NAME))
    else:
        print('[警告] 未找到 %s（跳过标题注入）' % src)

    emit_linux_png(os.path.join('linux', 'runner', 'resources', 'ogl_icon_2048.png'))


def main() -> int:
    if not os.path.exists(SVG):
        print('[失败] 找不到图标几何源：%s' % SVG)
        return 1
    targets = [arg for arg in sys.argv[1:] if not arg.startswith('-')]
    if not targets:
        targets = ['windows', 'linux']
    if 'windows' in targets:
        inject_windows()
    if 'linux' in targets:
        inject_linux()
    print('[自检通过] 桌面图标与原生标题已就位')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())