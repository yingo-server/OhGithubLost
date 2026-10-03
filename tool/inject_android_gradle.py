#!/usr/bin/env python3
"""把 Android 宿主的 `compileSdk` 提升到插件要求的版本（CI 护栏）。

为什么需要它（CI 实证过的坑）：
- `permission_handler_android` 要求宿主 `compileSdk` 高于 Flutter 模板默认值；
- 而本仓库**不提交平台目录**，`android/` 由 CI 用 `flutter create` 现场生成，
  因此无法直接改仓库里的 gradle 文件；
- 解决办法：构建期对生成物做**幂等注入**，把 compileSdk 抬到目标值。

幂等：已是目标值则不改；返回码 0 = 成功（无论是否有改动）。
用法：
    python3 tool/inject_android_gradle.py [--compile-sdk 37]
"""
import argparse
import os
import re
import sys

# 覆盖 groovy 与 kotlin-dsl 两套写法（含直接写数字与写 flutter.compileSdkVersion）。
PATTERNS = [
    (re.compile(r'compileSdkVersion\s+flutter\.compileSdkVersion'),
     'compileSdkVersion {v}'),
    (re.compile(r'compileSdk\s*=\s*flutter\.compileSdkVersion'),
     'compileSdk = {v}'),
    (re.compile(r'compileSdkVersion\s+\d+'),
     'compileSdkVersion {v}'),
    (re.compile(r'compileSdk\s*=\s*\d+'),
     'compileSdk = {v}'),
]

CANDIDATES = [
    'android/app/build.gradle.kts',
    'android/app/build.gradle',
]

# ── core library desugaring（flutter_local_notifications 要求）──────────────
#
# 为什么需要：`flutter_local_notifications` 从 v10 起依赖 Java 8+ API desugaring
# （低版本 Android 上支持定时通知等）。若不开启，Android 构建会直接失败。
# 平台目录由 CI 现场生成，因此同样在构建期做**幂等**注入。
DESUGAR_DEP = 'com.android.tools:desugar_jdk_libs:2.1.4'


def inject_desugaring(path):
    text = open(path, encoding='utf-8').read()
    if 'coreLibraryDesugaring' in text:
        print('[已存在] %s 已开启 core library desugaring' % path)
        return 0
    if path.endswith('.kts'):
        block = (
            '\n// OGL: flutter_local_notifications 需要 core library desugaring\n'
            'android {\n'
            '    compileOptions {\n'
            '        isCoreLibraryDesugaringEnabled = true\n'
            '        sourceCompatibility = JavaVersion.VERSION_17\n'
            '        targetCompatibility = JavaVersion.VERSION_17\n'
            '    }\n'
            '}\n'
            'dependencies {\n'
            '    coreLibraryDesugaring("%s")\n'
            '}\n' % DESUGAR_DEP
        )
    else:
        block = (
            '\n// OGL: flutter_local_notifications 需要 core library desugaring\n'
            'android {\n'
            '    compileOptions {\n'
            '        coreLibraryDesugaringEnabled true\n'
            '        sourceCompatibility JavaVersion.VERSION_17\n'
            '        targetCompatibility JavaVersion.VERSION_17\n'
            '    }\n'
            '}\n'
            'dependencies {\n'
            "    coreLibraryDesugaring '%s'\n"
            '}\n' % DESUGAR_DEP
        )
    with open(path, 'a', encoding='utf-8') as handle:
        handle.write(block)
    text = open(path, encoding='utf-8').read()
    if 'coreLibraryDesugaring' not in text:
        print('[失败] 注入 desugaring 后仍未生效：%s' % path)
        return 1
    print('[注入] %s → core library desugaring' % path)
    return 0


def inject(path, target):
    text = open(path, encoding='utf-8').read()
    original = text
    for pattern, template in PATTERNS:
        text = pattern.sub(template.format(v=target), text)
        if text != original:
            break
    if text == original:
        # 可能是别的写法；至少确认文件里有 compileSdk 字样。
        if 'compileSdk' not in text:
            print('[失败] %s 里找不到 compileSdk 配置' % path)
            return 1
        print('[已存在] %s 的 compileSdk 已是目标形态' % path)
        return 0
    open(path, 'w', encoding='utf-8').write(text)
    print('[注入] %s → compileSdk %s' % (path, target))
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compile-sdk', default='37')
    parser.add_argument('--root', default='.')
    args = parser.parse_args()

    found = None
    for rel in CANDIDATES:
        candidate = os.path.join(args.root, rel)
        if os.path.exists(candidate):
            found = candidate
            break
    if found is None:
        print('[跳过] 未见 android/app/build.gradle(.kts)（非 Android 构建？）')
        return 0

    code = inject(found, args.compile_sdk)
    if code != 0:
        return code

    # ② core library desugaring（flutter_local_notifications 要求）。
    code = inject_desugaring(found)
    if code != 0:
        return code

    # 自检：注入后必须能在文件里看到目标 compileSdk。
    text = open(found, encoding='utf-8').read()
    if str(args.compile_sdk) not in text:
        print('[失败] 注入后仍未看到 compileSdk %s' % args.compile_sdk)
        return 1
    if 'coreLibraryDesugaring' not in text:
        print('[失败] 注入后仍未看到 coreLibraryDesugaring')
        return 1
    print('[自检通过] compileSdk %s 与 core library desugaring 均已就位'
          % args.compile_sdk)
    return 0


if __name__ == '__main__':
    sys.exit(main())
