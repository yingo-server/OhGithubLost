#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · Linux 发布形态：deb / rpm / AppImage（**裸放**，不再套外层压缩）。

## 为什么裸放
deb / rpm / AppImage **本身就是深度压缩格式**：再套一层 zip/7z 几乎压不动，
还迫使使用者解两次。所以 Linux 三种包直接作为 Release 产物上传。

## 三种格式
- `.deb`：手写 `DEBIAN/control` + 目录布局，`dpkg-deb -Zxz`（xz 极限）；
- `.rpm`：`rpmbuild -bb`，`%_binary_payload w9.xzdio`（xz 压缩级别上限 9）；
- `.AppImage`：AppDir + `AppRun` + `.desktop` + 图标（2048 母版），
  用 `appimagetool --appimage-extract-and-run`（**CI 无 FUSE** 的经典坑）。

任何一步不可用（缺工具 / 下载失败）都**只告警不失败**——不让 AppImage
拖垮整个发布流程。
"""

from __future__ import annotations

import argparse
import os
import shutil
import stat
import subprocess

APP = 'ohgithublost'
APP_NAME = 'OhGithubLost'
ICON_REL = os.path.join('linux', 'runner', 'resources', 'ogl_icon_2048.png')
DESKTOP = (
    '[Desktop Entry]\n'
    'Type=Application\n'
    'Name={name}\n'
    'Exec={exec}\n'
    'Icon={icon}\n'
    'Categories=Development;Utility;\n'
    'Terminal=false\n'
)


def run(cmd, env=None):
    """执行外部命令（失败抛异常，由调用方决定是否降级）。"""
    print('  $ ' + ' '.join(cmd))
    return subprocess.run(cmd, env=env, check=True)


def is_linux_dir(name: str) -> bool:
    """判断 `dist/` 下的条目是否是 Linux 产物目录。

    ★ 这里踩过一个坑，值得写下来：
    `build.yml` 里 `upload-artifact` 的 `name` 直接取 `${{ matrix.label }}`，
    而标签形如 **`Linux · x64`**（中间是「空格 + 中点 + 空格」），并不是
    `Linux.x64`。原先这里只认 `Linux.` 前缀，于是**一个目录都匹配不到**，
    脚本静默地报「Linux 安装包 0 个」—— 加上发布作业当时又没签出仓库，
    两个问题叠加，导致 deb / rpm / AppImage 连续若干个版本从未产出。

    所以这里放宽为「以 Linux 开头」，不假设分隔符。
    """
    return name.strip().lower().startswith('linux')

def arch_of(name: str) -> tuple[str, str]:
    """`Linux · x64` / `Linux.x64` → (deb 架构, rpm 架构)。"""
    if 'arm64' in name or 'aarch64' in name:
        return 'arm64', 'aarch64'
    return 'amd64', 'x86_64'


def bundle_of(dist: str, name: str) -> str:
    """定位 Flutter 的 Linux bundle 目录（含可执行文件与 data/）。"""
    root = os.path.join(dist, name)
    for candidate in (root, os.path.join(root, 'bundle')):
        if os.path.isdir(candidate):
            return candidate
    return root


def find_exe(bundle: str) -> str:
    """bundle 里那个可执行文件（跳过 .so 与 lib*）。"""
    if os.path.isdir(bundle):
        for entry in sorted(os.listdir(bundle)):
            path = os.path.join(bundle, entry)
            if not os.path.isfile(path) or not os.access(path, os.X_OK):
                continue
            if entry.endswith('.so') or entry.startswith('lib'):
                continue
            return entry
    return APP


def make_deb(bundle: str, out: str, version: str, deb_arch: str) -> str | None:
    """生成 .deb（安装到 /opt，附 .desktop 与 hicolor 图标）。"""
    if shutil.which('dpkg-deb') is None:
        print('  [跳过] 没有 dpkg-deb')
        return None
    stage = os.path.join(out, '_deb_' + deb_arch)
    shutil.rmtree(stage, ignore_errors=True)
    opt = os.path.join(stage, 'opt', APP)
    os.makedirs(os.path.dirname(opt), exist_ok=True)
    shutil.copytree(bundle, opt)

    with open(os.path.join(_mkdir(stage, 'DEBIAN'), 'control'), 'w', encoding='utf-8') as handle:
        handle.write(
            'Package: %s\nVersion: %s\nSection: utils\nPriority: optional\n'
            'Architecture: %s\nMaintainer: OhGithubLost <noreply@example.com>\n'
            'Description: %s - GitHub repository manager (Flutter desktop).\n'
            % (APP, version, deb_arch, APP_NAME)
        )

    desktop_dir = _mkdir(stage, 'usr/share/applications')
    with open(os.path.join(desktop_dir, APP + '.desktop'), 'w', encoding='utf-8') as handle:
        handle.write(DESKTOP.format(name=APP_NAME, exec='/opt/%s/%s' % (APP, APP), icon=APP))

    if os.path.exists(ICON_REL):
        icon_dir = _mkdir(stage, 'usr/share/icons/hicolor/256x256/apps')
        shutil.copyfile(ICON_REL, os.path.join(icon_dir, APP + '.png'))

    deb = os.path.join(out, '%s_%s_%s.deb' % (APP, version, deb_arch))
    run(['dpkg-deb', '-Zxz', '--build', stage, deb])
    shutil.rmtree(stage, ignore_errors=True)
    return deb


def make_rpm(bundle: str, out: str, version: str, rpm_arch: str) -> str | None:
    """生成 .rpm（xz 极限载荷）。

    规格文件用 `%{buildroot}` 承载整棵 bundle；`.desktop` 与图标通过
    `%install` 阶段的 `install -D` 从**已准备的源文件**复制，避免在 spec 里
    写长串转义字符串（那正是最容易出错的地方）。

    ⚠️ 两个踩过的坑：
    1. **`_topdir` 必须是绝对路径**。此前传的是相对路径，而 rpmbuild 在
       `%install` 阶段会切换工作目录，于是 `%{_sourcedir}` 展开后指向别处，
       报 `cp: cannot stat '.../SOURCES/bundle/.'`。
    2. **跨架构构建要显式 `--target`**，否则报
       `No compatible architectures found for build`。
    """
    if shutil.which('rpmbuild') is None:
        print('  [跳过] 没有 rpmbuild')
        return None
    top = os.path.abspath(os.path.join(out, '_rpm', rpm_arch))
    for sub in ('BUILD', 'RPMS', 'SOURCES', 'SPECS', 'SRPMS'):
        os.makedirs(os.path.join(top, sub), exist_ok=True)

    payload = os.path.join(top, 'SOURCES', 'bundle')
    shutil.rmtree(payload, ignore_errors=True)
    shutil.copytree(bundle, payload)

    desktop_src = os.path.join(top, 'SOURCES', APP + '.desktop')
    with open(desktop_src, 'w', encoding='utf-8') as handle:
        handle.write(DESKTOP.format(name=APP_NAME, exec='/opt/%s/%s' % (APP, APP), icon=APP))

    icon_src = os.path.join(top, 'SOURCES', APP + '.png')
    has_icon = os.path.exists(ICON_REL)
    if has_icon:
        shutil.copyfile(ICON_REL, icon_src)

    lines = [
        'Name: ' + APP,
        'Version: ' + version,
        'Release: 1',
        'Summary: ' + APP_NAME + ' desktop client',
        'License: AGPL-3.0',
        'BuildArch: ' + rpm_arch,
        '%define _binary_payload w9.xzdio',
        '',
        '%description',
        APP_NAME + ' - GitHub repository manager (Flutter desktop).',
        '',
        '%install',
        'rm -rf %{buildroot}',
        'install -d %{buildroot}/opt/' + APP,
        'cp -a %{_sourcedir}/bundle/. %{buildroot}/opt/' + APP + '/',
        'install -D -m 644 %{_sourcedir}/' + APP + '.desktop %{buildroot}%{_datadir}/applications/' + APP + '.desktop',
    ]
    if has_icon:
        lines.append(
            'install -D -m 644 %{_sourcedir}/' + APP + '.png '
            '%{buildroot}%{_datadir}/icons/hicolor/256x256/apps/' + APP + '.png'
        )
    lines += ['', '%files', '/opt/' + APP, '%{_datadir}/applications/' + APP + '.desktop']
    if has_icon:
        lines.append('%{_datadir}/icons/hicolor/256x256/apps/' + APP + '.png')

    spec = os.path.join(top, 'SPECS', APP + '.spec')
    with open(spec, 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(lines) + '\n')

    # `--target` 必须显式给：不指定时 rpmbuild 在 x86_64 宿主上构建 aarch64 包
    # 会直接报 `No compatible architectures found for build`。
    run(['rpmbuild', '-bb', '--target', rpm_arch,
         '--define', '_topdir ' + top, os.path.abspath(spec)])
    rpms = os.path.join(top, 'RPMS', rpm_arch)
    for name in sorted(os.listdir(rpms)):
        if name.endswith('.rpm'):
            target = os.path.join(out, name)
            shutil.copyfile(os.path.join(rpms, name), target)
            shutil.rmtree(os.path.join(out, '_rpm'), ignore_errors=True)
            return target
    return None


def host_appimage_arch() -> str:
    """宿主架构（appimagetool 只能运行**与宿主同架构**的二进制）。"""
    import platform  # noqa: PLC0415 - 仅此处需要
    machine = platform.machine().lower()
    if machine in ('aarch64', 'arm64'):
        return 'aarch64'
    return 'x86_64'

def make_appimage(bundle: str, out: str, version: str, deb_arch: str) -> str | None:
    """生成 AppImage（免 FUSE 运行 appimagetool）。

    ⚠️ 这里踩过一个很隐蔽的坑：
    原先按**目标架构**下载 appimagetool，且用 `if not os.path.exists(tool)` 缓存。
    `Linux · arm64` 在字典序上排在 `Linux · x64` 前面，于是先下载了 **aarch64**
    的 appimagetool；轮到 x86_64 时发现文件已存在便跳过下载，直接去跑那个
    aarch64 二进制 —— `Exec format error`。两个架构因此**全都失败**。

    正确做法：**始终下载宿主架构的 appimagetool**（它能运行），再用 `ARCH`
    环境变量告诉它目标架构，由它选用对应的 AppImage 运行时。
    缓存文件名带上宿主架构，避免跨架构复用。
    """
    host = host_appimage_arch()
    tool = os.path.abspath(os.path.join(out, '_appimagetool-%s' % host))
    if not os.path.exists(tool):
        url = (
            'https://github.com/AppImage/AppImageKit/releases/download/continuous/'
            'appimagetool-%s.AppImage' % host
        )
        try:
            run(['curl', '-sSL', '-o', tool, url])
        except Exception as error:  # noqa: BLE001
            print('  [跳过] 下载 appimagetool 失败：%s' % error)
            return None
        os.chmod(tool, os.stat(tool).st_mode | stat.S_IEXEC)

    out = os.path.abspath(out)
    appdir = os.path.abspath(os.path.join(out, APP_NAME + '.AppDir'))
    shutil.rmtree(appdir, ignore_errors=True)
    shutil.copytree(bundle, appdir)

    exe = find_exe(bundle)
    if os.path.exists(ICON_REL):
        shutil.copyfile(ICON_REL, os.path.join(appdir, '.DirIcon'))
        shutil.copyfile(ICON_REL, os.path.join(appdir, APP + '.png'))
    with open(os.path.join(appdir, APP + '.desktop'), 'w', encoding='utf-8') as handle:
        handle.write(DESKTOP.format(name=APP_NAME, exec=exe, icon=APP))
    app_run = os.path.join(appdir, 'AppRun')
    with open(app_run, 'w', encoding='utf-8') as handle:
        handle.write('#!/bin/sh\nHERE=$(dirname "$(readlink -f "$0")")\nexec "$HERE/%s" "$@"\n' % exe)
    os.chmod(app_run, os.stat(app_run).st_mode | stat.S_IEXEC)

    target = os.path.join(out, '%s-%s-%s.AppImage' % (APP, version, deb_arch))
    # AppImage 的运行时架构名与 deb 不同：deb 用 `arm64`，AppImage 用 `aarch64`。
    # 传错名字会让 appimagetool 找不到对应运行时。
    appimage_arch = 'aarch64' if deb_arch == 'arm64' else 'x86_64'
    try:
        run([tool, '--appimage-extract-and-run', appdir, target],
            env=dict(os.environ, ARCH=appimage_arch))
    except Exception as error:  # noqa: BLE001
        print('  [跳过] AppImage 打包失败：%s' % error)
        return None
    finally:
        shutil.rmtree(appdir, ignore_errors=True)
    return target


def _mkdir(*parts: str) -> str:
    """建目录并返回路径。"""
    path = os.path.join(*parts)
    os.makedirs(path, exist_ok=True)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description='把 Linux bundle 打成 deb / rpm / AppImage')
    parser.add_argument('--dist', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    made = 0
    for name in sorted(os.listdir(args.dist)):
        if not is_linux_dir(name):
            continue
        bundle = bundle_of(args.dist, name)
        deb_arch, rpm_arch = arch_of(name)
        print('== %s（%s）' % (name, bundle))
        for builder, arch in (
            (make_deb, deb_arch),
            (make_rpm, rpm_arch),
            (make_appimage, deb_arch),
        ):
            try:
                result = builder(bundle, args.out, args.version, arch)
            except Exception as error:  # noqa: BLE001
                print('  [告警] %s 失败：%s' % (builder.__name__, error))
                result = None
            if result:
                made += 1
                print('  → ' + result)

    # 清掉临时下载的 appimagetool：`out/` 目录会被整目录上传为 Release 产物，
    # 留下它就会把一个几 MB 的工具二进制也发出去。
    # 名字带宿主架构（见 make_appimage），所以按前缀匹配而不是写死文件名。
    for name in sorted(os.listdir(args.out)):
        if name.startswith('_appimagetool'):
            os.remove(os.path.join(args.out, name))
    for name in ('_rpm', '_deb_amd64', '_deb_arm64'):
        shutil.rmtree(os.path.join(args.out, name), ignore_errors=True)
    print('[完成] Linux 安装包 %d 个' % made)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())