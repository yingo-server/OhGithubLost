#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · Android 图标注入（**矢量 XML，透明背景**）。

## 为什么走矢量而不是 PNG
平台目录（`android/`）由 CI 现场生成，仓库里不留二进制图标；
把图标写成 **VectorDrawable**（纯文本）才能真正做到"一处修改、处处一致"，
也避免往仓库塞一堆不同倍率的 PNG。

## 内容来源
图标几何来自仓库的 `assets/icon/ogl_icon.svg` 同源图形（512×512 视口）：
- 本体：六边形（对角线性渐变 `#2F3441 → #171A21 → #08090C`）
- 双眼：两个三角（垂直渐变 `#FFE7A3 → #FFC93C → #D98E05`）
背景**完全透明**（原 SVG 没有背景矩形）。

## 做法
1. 写 `drawable/ic_launcher_foreground.xml`（矢量前景）；
2. 写 `mipmap-anydpi-v26/ic_launcher.xml` 与 `ic_launcher_round.xml`
   （自适应图标，背景透明）；
3. 把 `AndroidManifest.xml` 的 `android:label` 改成 **OGL**。
   > 自适应图标的前景只保证中央 66/108 区域可见，所以矢量内容整体
   > **缩放到 0.62 并居中**，避免被圆形/方形遮罩裁掉尖角。

API < 26 的旧设备仍使用 Flutter 模板自带的 PNG 兜底（不阻塞）。
用法：
    python3 tool/inject_android_icon.py [android_dir]
"""
import os
import re
import sys

# ── 前景矢量（透明背景）──────────────────────────────────────────────
FOREGROUND = '''<?xml version="1.0" encoding="utf-8"?>
<!-- OGL launcher foreground（自动生成：tool/inject_android_icon.py） -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="512"
    android:viewportHeight="512">
    <!-- 自适应图标只保证中央 66/108 可见 → 整体缩到 0.62 并居中 -->
    <group
        android:pivotX="256"
        android:pivotY="256"
        android:scaleX="0.62"
        android:scaleY="0.62">
        <!-- 本体：六边形（对角线性渐变） -->
        <path android:pathData="M128,96 L256,192 L384,96 L416,320 L256,448 L96,320 Z">
            <aapt:attr name="android:fillColor">
                <gradient
                    android:type="linear"
                    android:startX="0"
                    android:startY="0"
                    android:endX="512"
                    android:endY="512">
                    <item android:offset="0" android:color="#FF2F3441" />
                    <item android:offset="0.5" android:color="#FF171A21" />
                    <item android:offset="1" android:color="#FF08090C" />
                </gradient>
            </aapt:attr>
        </path>
        <!-- 左眼 -->
        <path android:pathData="M160,256 L224,256 L192,320 Z">
            <aapt:attr name="android:fillColor">
                <gradient
                    android:type="linear"
                    android:startX="0"
                    android:startY="0"
                    android:endX="0"
                    android:endY="512">
                    <item android:offset="0" android:color="#FFFFE7A3" />
                    <item android:offset="0.5" android:color="#FFFFC93C" />
                    <item android:offset="1" android:color="#FFD98E05" />
                </gradient>
            </aapt:attr>
        </path>
        <!-- 右眼 -->
        <path android:pathData="M288,256 L352,256 L320,320 Z">
            <aapt:attr name="android:fillColor">
                <gradient
                    android:type="linear"
                    android:startX="0"
                    android:startY="0"
                    android:endX="0"
                    android:endY="512">
                    <item android:offset="0" android:color="#FFFFE7A3" />
                    <item android:offset="0.5" android:color="#FFFFC93C" />
                    <item android:offset="1" android:color="#FFD98E05" />
                </gradient>
            </aapt:attr>
        </path>
    </group>
</vector>
'''

# ── 自适应图标（背景透明）────────────────────────────────────────────
ADAPTIVE = '''<?xml version="1.0" encoding="utf-8"?>
<!-- OGL adaptive icon（自动生成）：背景**透明**，前景为矢量 -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/transparent" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
'''

# 应用显示名：Android = OGL（其余平台为 OhGithubLost）
ANDROID_LABEL = 'OGL'


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)
    print('  写入 %s' % os.path.relpath(path))


def patch_manifest(manifest):
    if not os.path.exists(manifest):
        print('  ! 找不到 AndroidManifest.xml，跳过 label')
        return
    with open(manifest, encoding='utf-8') as handle:
        text = handle.read()
    # 只改 <application> 上的 android:label
    new, count = re.subn(
        r'(<application\b[^>]*?android:label=")[^"]*(")',
        lambda m: m.group(1) + ANDROID_LABEL + m.group(2),
        text,
        count=1,
    )
    if count == 0:
        # 没有 label 属性就插进去
        new, count = re.subn(
            r'<application\b',
            '<application\\n        android:label="%s"' % ANDROID_LABEL,
            text,
            count=1,
        )
    if count == 0:
        print('  ! 未找到 <application>，label 未修改')
        return
    with open(manifest, 'w', encoding='utf-8') as handle:
        handle.write(new)
    print('  AndroidManifest android:label → %s' % ANDROID_LABEL)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'android'
    if not os.path.isdir(root):
        print('跳过：目录不存在 %s（非 Android 构建）' % root)
        return 0
    res = os.path.join(root, 'app', 'src', 'main', 'res')
    write(os.path.join(res, 'drawable', 'ic_launcher_foreground.xml'), FOREGROUND)
    write(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), ADAPTIVE)
    write(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher_round.xml'), ADAPTIVE)
    patch_manifest(os.path.join(root, 'app', 'src', 'main', 'AndroidManifest.xml'))
    print('Android 图标注入完成（矢量 / 透明背景 / label=%s）' % ANDROID_LABEL)
    return 0


if __name__ == '__main__':
    sys.exit(main())