#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`inject_platform_spec.py` 的自检（不碰真实平台目录）。

用**临时目录里的假脚手架**验证：解析（含零依赖兜底解析器）、双 DSL 注入、
幂等、逐项注入，以及"缺 why / 缺目标文件必须拒绝"。
退出码 0 = 全部通过（可直接挂 CI）。
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, 'tool', 'inject_platform_spec.py')

# Flutter 3.47.5 实际生成的 Kotlin DSL 模板（注意：无 desugaring 相关行）。
FAKE_GRADLE_KTS = """plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yingo.ohgithublost"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "com.yingo.ohgithublost"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.debug
        }
    }
}

flutter {
    source = "../.."
}
"""

# Flutter 3.47.5 的模板**没有**顶层 dependencies 块（默认无依赖可声明），
# 故上面的夹具刻意不含它 —— 真实路径就是"新建一个 dependencies 块"。

# 旧 Groovy 模板：同样必须能被注入命中（向下兼容，不因模板回退而失效）。
FAKE_GRADLE_GROOVY = """plugins {
    id "com.android.application"
}

android {
    compileSdkVersion flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
}
"""

# 模板里**已存在** dependencies 块的情形（部分插件模板 / 用户已有工程）。
FAKE_GRADLE_WITH_DEPS = FAKE_GRADLE_KTS.replace(
    'flutter {\n    source = "../.."\n}',
    'dependencies {\n    implementation("androidx.core:core-ktx:1.13.1")\n}\n'
    '\nflutter {\n    source = "../.."\n}')

FAKE_MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="ohgithublost"
        android:name="${applicationName}">
    </application>
</manifest>
"""

FAKE_CMAKE = """cmake_minimum_required(VERSION 3.10)
project(runner LANGUAGES CXX)

# 运行库与宏
add_definitions(-DUNICODE -D_UNICODE)
"""

FAILURES = []


def check(name, ok, detail=''):
    print('  %s %s' % ('✓' if ok else '✗', name))
    if not ok:
        FAILURES.append('%s %s' % (name, detail))


def run(workspace, *args, **kwargs):
    env = kwargs.get('env')
    # ★ cwd 必须是临时目录：万一注入器内部再出现相对路径，
    #   泄漏的也只会是临时目录，而**不是仓库根**（曾真的在仓库里
    #   建出 android/ 与 linux/runner/）。
    return subprocess.run(
        [sys.executable, TOOL, '--root', workspace] + list(args),
        capture_output=True, text=True, cwd=workspace,
        env=env or os.environ.copy())


def read(path):
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def repo_is_clean():
    """仓库根不应被注入器写入任何东西。"""
    leaked = [name for name in ('android', 'linux', 'windows', 'macos', 'ios')
              if os.path.exists(os.path.join(ROOT, name))]
    return not leaked, leaked


def write_fake_tree(base):
    """铺一套假脚手架，返回关键文件路径。"""
    os.makedirs(os.path.join(base, 'android', 'app', 'src', 'main'))
    os.makedirs(os.path.join(base, 'windows', 'runner'))
    os.makedirs(os.path.join(base, 'linux', 'runner', 'resources'))
    gradle = os.path.join(base, 'android', 'app', 'build.gradle.kts')
    manifest = os.path.join(base, 'android', 'app', 'src', 'main',
                            'AndroidManifest.xml')
    cmake = os.path.join(base, 'windows', 'CMakeLists.txt')
    with open(gradle, 'w', encoding='utf-8') as fh:
        fh.write(FAKE_GRADLE_KTS)
    with open(manifest, 'w', encoding='utf-8') as fh:
        fh.write(FAKE_MANIFEST)
    with open(cmake, 'w', encoding='utf-8') as fh:
        fh.write(FAKE_CMAKE)
    return gradle, manifest, cmake


def main():
    tmp = tempfile.mkdtemp(prefix='ogl-spec-')
    try:
        gradle, manifest, cmake = write_fake_tree(tmp)
        # 图标注入需要真实的 SVG 源，复制一份进来（与 CI 里同源）。
        os.makedirs(os.path.join(tmp, 'assets', 'icon'), exist_ok=True)
        shutil.copy(os.path.join(ROOT, 'assets', 'icon', 'ogl_icon.svg'),
                    os.path.join(tmp, 'assets', 'icon', 'ogl_icon.svg'))

        print('① Android 注入（Kotlin DSL 模板）')
        r1 = run(tmp, '--target', 'android')
        check('退出码 0', r1.returncode == 0, r1.stderr[:300])
        gradle_text = read(gradle)
        manifest_text = read(manifest)
        check('compileSdk 已标记', 'OGL_PLATFORM_SPEC compileSdk' in gradle_text)
        check('desugaring 已标记', 'OGL_PLATFORM_SPEC desugaring' in gradle_text)
        # ★ 必须是 37：permission_handler_android 要求 37+（CI 实证）。
        check('compileSdk 已抬到 37',
              re.search(r'compileSdk\s*=\s*37', gradle_text) is not None,
              gradle_text[:200])
        check('flutter.compileSdkVersion 引用已被替换',
              'flutter.compileSdkVersion' not in gradle_text)
        check('幂等标记只出现一次',
              gradle_text.count('OGL_PLATFORM_SPEC compileSdk') == 1,
              gradle_text[:300])
        # ★ desugaring 依赖必须真的声明（只在 compileOptions 里打开开关不够，
        #   Gradle 仍会报 "requires core library desugaring to be enabled"）。
        check('desugar 依赖已声明',
              'com.android.tools:desugar_jdk_libs' in gradle_text)
        # ★ Kotlin DSL 必须用 Kotlin 语法，否则 Gradle 直接语法错误。
        check('开关用 Kotlin 语法 isCoreLibraryDesugaringEnabled',
              'isCoreLibraryDesugaringEnabled = true' in gradle_text,
              gradle_text[:400])
        check('依赖用 Kotlin 语法 coreLibraryDesugaring("…")',
              re.search(r'coreLibraryDesugaring\(\s*"com\.android\.tools',
                        gradle_text) is not None)
        check('未混入 Groovy 单引号语法',
              "coreLibraryDesugaring '" not in gradle_text)
        check('INTERNET 已声明', 'android.permission.INTERNET' in manifest_text)
        check('MANAGE_EXTERNAL_STORAGE 已声明',
              'MANAGE_EXTERNAL_STORAGE' in manifest_text)
        check('requestLegacyExternalStorage 已处理',
              'requestLegacyExternalStorage' in manifest_text)
        check('label 已改 OGL', 'android:label="OGL"' in manifest_text)
        check('图标前景已写入',
              os.path.isfile(os.path.join(
                  tmp, 'android', 'app', 'src', 'main', 'res', 'drawable',
                  'ic_launcher_foreground.xml')))

        print('② 幂等（重跑不应改内容、不报错）')
        before = (gradle_text, manifest_text)
        r2 = run(tmp, '--target', 'android')
        check('退出码 0', r2.returncode == 0, r2.stderr[:300])
        check('build.gradle.kts 未变化', read(gradle) == before[0])
        check('AndroidManifest 未变化', read(manifest) == before[1])

        print('③ Windows 注入')
        r3 = run(tmp, '--target', 'windows')
        check('退出码 0', r3.returncode == 0, r3.stderr[:300])
        cmake_text = read(cmake)
        check('编译宏已注入', 'add_compile_definitions' in cmake_text)
        check('幂等标记已写入', 'OGL_PLATFORM_SPEC' in cmake_text)
        # ★ MSVC 14.5x（VS2026）对 <experimental/coroutine> 报 STL1011，
        #   点名要的宏就是这个（CI 实证）。
        check('含 _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS',
              '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS'
              in cmake_text, cmake_text[:200])
        check('不再全局关闭 C++ 异常',
              '_HAS_EXCEPTIONS=0' not in cmake_text)
        check('宏加在所有 add_subdirectory 之前',
              cmake_text.index('add_compile_definitions')
              < cmake_text.find('add_subdirectory')
              if 'add_subdirectory' in cmake_text else True)
        check('ICO 已写入',
              os.path.isfile(os.path.join(tmp, 'windows', 'runner', 'resources',
                                          'app_icon.ico')))

        print('④ Linux 注入')
        r4 = run(tmp, '--target', 'linux')
        check('退出码 0', r4.returncode == 0, r4.stderr[:300])
        check('PNG 已写入',
              os.path.isfile(os.path.join(tmp, 'linux', 'runner', 'resources',
                                          'app_icon.png')))

        print('⑤ 单 job 过滤')
        r5 = run(tmp, '--target', 'android', '--job', 'android-icon')
        check('只跑指定 job 退出码 0', r5.returncode == 0, r5.stderr[:300])
        check('输出只含该 job', 'android-icon' in r5.stdout)

        print('⑥ 缺 why 必须拒绝（防止注入成为逃生舱）')
        bad = os.path.join(tmp, 'bad_spec.yaml')
        with open(bad, 'w', encoding='utf-8') as fh:
            fh.write('spec_version: 1\nspecs:\n  - target: android\n'
                     '    id: x\n    steps:\n      - file: nope.txt\n'
                     '        patch: set_app_label\n')
        r6 = subprocess.run(
            [sys.executable, TOOL, '--root', tmp, '--target', 'android',
             '--spec', bad], capture_output=True, text=True)
        check('退出码非 0', r6.returncode != 0)
        check('明确提示缺 why', 'why' in (r6.stderr + r6.stdout))

        print('⑦ 未知平台必须报错（spec 里没有该平台条目 = 漏读或漏写）')
        r7 = run(tmp, '--target', 'plan9')
        check('退出码非 0', r7.returncode != 0, r7.stdout[:200])
        check('明确提示无该平台条目',
              '没有' in r7.stderr or '没有' in r7.stdout)

        print('⑧ 仓库根未被污染（不许建出 android/ linux/ 等）')
        clean, leaked = repo_is_clean()
        check('仓库根干净', clean, '泄漏：%s' % '、'.join(leaked))

        print('⑨ Groovy 旧模板同样能注入（模板回退也不失效）')
        groovy_dir = os.path.join(tmp, 'groovy')
        os.makedirs(os.path.join(groovy_dir, 'android', 'app'))
        groovy_spec = os.path.join(groovy_dir, 'spec.yaml')
        with open(groovy_spec, 'w', encoding='utf-8') as fh:
            fh.write('spec_version: 1\nspecs:\n'
                     '  - target: android\n'
                     '    id: g\n'
                     '    why: 测试 Groovy 模板\n'
                     '    steps:\n'
                     '      - file: android/app/build.gradle\n'
                     '        patch: compile_sdk\n'
                     '        compile_sdk: 37\n'
                     '      - file: android/app/build.gradle\n'
                     '        patch: core_library_desugaring\n')
        groovy_gradle = os.path.join(groovy_dir, 'android', 'app', 'build.gradle')
        with open(groovy_gradle, 'w', encoding='utf-8') as fh:
            fh.write(FAKE_GRADLE_GROOVY)
        rg = subprocess.run(
            [sys.executable, TOOL, '--root', groovy_dir, '--spec', groovy_spec,
             '--target', 'android'], capture_output=True, text=True,
            cwd=groovy_dir)
        check('Groovy 退出码 0', rg.returncode == 0, rg.stderr[:300])
        groovy_text = read(groovy_gradle)
        check('Groovy compileSdk 已抬到 37',
              re.search(r'compileSdkVersion\s+37', groovy_text) is not None,
              groovy_text[:200])
        check('Groovy desugar 依赖用单引号',
              "coreLibraryDesugaring 'com.android.tools" in groovy_text)
        check('Groovy 未混入 Kotlin 语法',
              'isCoreLibraryDesugaringEnabled' not in groovy_text)

        print('⑩ 零依赖兜底解析器（模拟无 PyYAML 的 Windows/Linux runner）')
        # GitHub 的 Windows runner 不带 PyYAML，注入器会走手写兜底解析器。
        # 曾经它几乎解析不出东西 → "规格中没有 windows 的条目" → 两条腿全红。
        blocker = os.path.join(tmp, '_noyaml')
        os.makedirs(blocker, exist_ok=True)
        with open(os.path.join(blocker, 'yaml.py'), 'w', encoding='utf-8') as fh:
            fh.write('raise ImportError("selftest: 模拟 runner 无 PyYAML")\n')
        noyaml_env = os.environ.copy()
        noyaml_env['PYTHONPATH'] = blocker
        r10 = run(tmp, '--list', env=noyaml_env)
        check('无 PyYAML 退出码 0', r10.returncode == 0, r10.stderr[:300])
        for target, spec_id in (('android', 'android-compile-sdk'),
                                ('windows', 'windows-compat-macro'),
                                ('windows', 'windows-icon'),
                                ('linux', 'linux-icon'),
                                ('macos', 'macos-entitlements')):
            check('无 PyYAML 仍能列出 %s/%s' % (target, spec_id),
                  spec_id in r10.stdout, r10.stdout[:300])
        # 且注入本身也要能跑通（不只是能列）。
        fresh_dir = os.path.join(tmp, 'noyaml_run')
        g2, _, _ = write_fake_tree(fresh_dir)
        os.makedirs(os.path.join(fresh_dir, 'assets', 'icon'), exist_ok=True)
        shutil.copy(os.path.join(ROOT, 'assets', 'icon', 'ogl_icon.svg'),
                    os.path.join(fresh_dir, 'assets', 'icon', 'ogl_icon.svg'))
        r10b = run(fresh_dir, '--target', 'windows', env=noyaml_env)
        check('无 PyYAML 时 Windows 注入退出码 0',
              r10b.returncode == 0, r10b.stderr[:300])
        check('无 PyYAML 时编译宏仍注入',
              'add_compile_definitions' in read(
                  os.path.join(fresh_dir, 'windows', 'CMakeLists.txt')))

        print('⑪ 缺目标文件必须报错（不再静默跳过）')
        missing_dir = os.path.join(tmp, 'missing')
        os.makedirs(missing_dir)
        rm = run(missing_dir, '--target', 'android')
        check('退出码非 0', rm.returncode != 0, rm.stdout[:200])
        check('明确指出缺 build.gradle.kts',
              'build.gradle.kts' in (rm.stderr + rm.stdout),
              (rm.stderr + rm.stdout)[:300])

        print('⑫ 模板已存在 dependencies 块时，依赖插进块内而非新建')
        deps_dir = os.path.join(tmp, 'withdeps')
        write_fake_tree(deps_dir)
        deps_gradle = os.path.join(deps_dir, 'android', 'app',
                                  'build.gradle.kts')
        with open(deps_gradle, 'w', encoding='utf-8') as fh:
            fh.write(FAKE_GRADLE_WITH_DEPS)
        os.makedirs(os.path.join(deps_dir, 'assets', 'icon'), exist_ok=True)
        shutil.copy(os.path.join(ROOT, 'assets', 'icon', 'ogl_icon.svg'),
                    os.path.join(deps_dir, 'assets', 'icon', 'ogl_icon.svg'))
        rd = run(deps_dir, '--target', 'android')
        check('含 dependencies 模板退出码 0', rd.returncode == 0,
              rd.stderr[:300])
        deps_text = read(deps_gradle)
        check('desugar 依赖已声明',
              'com.android.tools:desugar_jdk_libs' in deps_text)
        check('未重复新建 dependencies 块',
              deps_text.count('dependencies {') == 1,
              deps_text[-400:])
        check('原有依赖未被破坏',
              'androidx.core:core-ktx' in deps_text)

        print()
        if FAILURES:
            print('自检失败 %d 项：' % len(FAILURES))
            for item in FAILURES:
                print('  - %s' % item)
            return 1
        print('自检全部通过')
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())