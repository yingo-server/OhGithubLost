#!/usr/bin/env python3
"""把**日志/网络所需的 Android 权限**注入 Flutter 模板生成的主清单。

为什么需要它（CI 实证过的坑）：
- Flutter 模板的 `INTERNET` 只在 debug/profile 清单里，release 主清单**没有** ——
  不注入的话安装包能启动，但任何网络请求直接失败；
- 日志要写到 `sdcard/logging`（用户明确要求）：
  - Android ≤ 9：需要 `WRITE/READ_EXTERNAL_STORAGE`（运行时授权后可用）；
  - Android 10：需要 `requestLegacyExternalStorage`（旧式存储）；
  - Android 11+：根目录写入需要 `MANAGE_EXTERNAL_STORAGE`（"所有文件访问"，
    由用户在系统设置里授予；未授予时应用会自动回退到外部目录，
    并把"写到哪 / 为什么没写到 sdcard"显示在关于页）。
  三者都声明，才能让**任一系统版本**上都存在"写到 sdcard/logging"的路径。

幂等：重复执行不会重复注入；返回码 0 = 成功（无论是否有改动）。
用法：
    python3 tool/inject_android_manifest.py [--manifest <path>]
"""

import argparse
import os
import sys

PERMISSIONS = [
    ('android.permission.INTERNET', None,
     '网络：GitHub API 必需（release 主清单默认没有）'),
    ('android.permission.POST_NOTIFICATIONS', None,
     '通知：Android 13+ 主动提示（限流 / 下载完成等）需运行时授权'),
    ('android.permission.MANAGE_EXTERNAL_STORAGE', None,
     '日志：Android 11+ 写 /sdcard/logging 需"所有文件访问"'),
    ('android.permission.READ_EXTERNAL_STORAGE', '32',
     '日志：Android ≤ 12 读取外部目录'),
    ('android.permission.WRITE_EXTERNAL_STORAGE', '29',
     '日志：Android ≤ 10 写入外部目录'),
]


def inject(manifest_path):
    if not os.path.exists(manifest_path):
        print('[跳过] 找不到清单：%s' % manifest_path)
        return 0
    text = open(manifest_path, encoding='utf-8').read()
    changed = []

    # ① 权限：逐个检查，缺谁补谁（按 PERMISSIONS 顺序一次性拼块）。
    missing = []
    for name, max_sdk, why in PERMISSIONS:
        if name in text:
            continue
        attr = '' if max_sdk is None else ' android:maxSdkVersion="%s"' % max_sdk
        missing.append(
            '    <uses-permission android:name="%s"%s /> <!-- %s -->'
            % (name, attr, why)
        )
    if missing:
        block = '\n'.join(missing) + '\n'
        if '<application' not in text:
            print('[失败] 清单里没有 <application> 标签，无法注入')
            return 1
        text = text.replace('<application', block + '    <application', 1)
        changed.append('%d 个权限' % len(missing))

    # ② Android 10 旧式存储（让 /sdcard 根写入在 Q 上继续可用）。
    if 'requestLegacyExternalStorage' not in text:
        text = text.replace(
            '<application',
            '<application android:requestLegacyExternalStorage="true"',
            1,
        )
        changed.append('requestLegacyExternalStorage')

    if changed:
        open(manifest_path, 'w', encoding='utf-8').write(text)
        print('[注入] %s → %s' % (manifest_path, '、'.join(changed)))
    else:
        print('[已存在] %s（无需改动）' % manifest_path)

    # ③ 自检：注入后必须能在清单里看到这些关键项。
    fail = []
    for name, _, _ in PERMISSIONS:
        if name not in text:
            fail.append(name)
    if fail:
        print('[失败] 注入后仍缺少：%s' % '、'.join(fail))
        return 1
    print('[自检通过] INTERNET + 存储权限齐全')
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--manifest',
        default='android/app/src/main/AndroidManifest.xml',
    )
    args = parser.parse_args()
    return inject(args.manifest)


if __name__ == '__main__':
    sys.exit(main())