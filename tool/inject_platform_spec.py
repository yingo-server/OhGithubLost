#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 平台私有文件注入器（读 `tool/platform_spec.yaml`，按需注入）。

## 定位
`platform_spec.yaml` 声明**物理上写不了 Dart** 的平台私有文件（安装期权限、
编译期宏、编译期属性、图标资源）。本脚本把它翻译成**当下那一版**脚手架里的
具体改动 —— 因为平台工程由 `flutter create` 在构建时现场生成，不能入库。

凡是 spec 里没写的，能力都必须在 `lib/platform/` 里用 Dart 实现。
**这里不是逃生舱**：新增注入项必须同时在 spec 里写清 `why`。

## 幂等
每个 step 都有 `marker`；文件里已有该标记即跳过，重跑安全。

## 用法
    python3 tool/inject_platform_spec.py --target android
    python3 tool/inject_platform_spec.py --target android --job android-icon
    python3 tool/inject_platform_spec.py --target windows --python python
    python3 tool/inject_platform_spec.py --list
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, 'tool', 'platform_spec.yaml')

DESUGAR_DEP = 'com.android.tools:desugar_jdk_libs:2.1.4'

# 这些 patch 是**凭空创建**文件，目标本来就不存在；其余 patch 都是**修改已有
# 文件**，目标缺失即代表 spec 与模板脱节，必须报错（见 main）。
CREATE_PATCHES = frozenset((
    'write_vector_xml',
    'write_adaptive_icon_xml',
    'write_ico',
    'write_png',
))

# Android 自适应图标（几何源 assets/icon/ogl_icon.svg，见 inject_android_icon.py）。
ADAPTIVE_ICON = """<?xml version="1.0" encoding="utf-8"?>
<!-- OGL_PLATFORM_SPEC icon -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/transparent" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""

FOREGROUND_ICON = """<?xml version="1.0" encoding="utf-8"?>
<!-- OGL_PLATFORM_SPEC icon -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M54,26 L78,36 L78,56 C78,70 68,80 54,86 C40,80 30,70 30,56 L30,36 Z" />
    <path
        android:fillColor="#FF3A7AFE"
        android:pathData="M46,48 L46,68 L64,58 Z" />
</vector>
"""

PERMISSION_BLOCK = """    <!-- OGL_PLATFORM_SPEC permissions -->
{perms}"""


def _load_spec(path):
    """极简 YAML 读取：只支持本文件用到的子集（列表 + 缩进映射 + `>` 折叠）。

    刻意不引入 PyYAML：CI 里 `pip install` 不保证成功，而门禁脚本必须
    零依赖可跑。
    """
    try:
        import yaml  # noqa: PLC0415 - 可用就用，缺失走下面的兜底
    except ImportError:
        return _parse_minimal_yaml(path)

    with open(path, encoding='utf-8') as handle:
        return yaml.safe_load(handle)


def _strip_comment(line: str) -> str:
    out = []
    quote = None
    for ch in line:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ('"', "'"):
            quote = ch
            out.append(ch)
            continue
        if ch == '#':
            break
        out.append(ch)
    return ''.join(out).rstrip()


def _scalar(text: str):
    text = text.strip()
    if not text:
        return None
    if text[0] in ('"', "'") and text[-1] == text[0] and len(text) >= 2:
        inner = text[1:-1]
        if text[0] == '"':
            # 双引号标量支持反斜杠转义（spec 里用它写 `android:label="OGL"`）。
            return inner.replace('\\"', '"').replace('\\\\', '\\')
        # 单引号标量里只有 '' 表示一个引号。
        return inner.replace("''", "'")
    if text in ('true', 'True'):
        return True
    if text in ('false', 'False'):
        return False
    if re.fullmatch(r'-?\d+', text):
        return int(text)
    if text.startswith('>') or text.startswith('|'):
        return text[1:].strip()
    return text


def _split_kv(body: str):
    """拆 `key: value`。

    YAML 规则：**只有** `:` 后跟空格（或行尾）才是键分隔符。
    因此 `- android:requestLegacyExternalStorage` 整体是一个标量，
    不是 `{android: requestLegacyExternalStorage}`。
    """
    quote = None
    for pos, ch in enumerate(body):
        if quote:
            if ch == quote:
                quote = None
            continue
        if ch in ('"', "'"):
            quote = ch
            continue
        if ch == ':' and (pos + 1 == len(body) or body[pos + 1] in ' \t'):
            return body[:pos].strip(), body[pos + 1:].strip()
    return None, None


def _tokenize_yaml(path: str):
    """把源行折叠成 `(indent, body, folded)` 三元组序列。

    在**词法阶段**就把 `key: >` / `key: |` 的块内容合并进同一行，
    解析器因此只需面对两种结构：映射与列表（缩进决定归属）。
    """
    raw: list = []
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            raw.append(_strip_comment(line).rstrip())

    out: list = []
    index = 0
    total = len(raw)
    while index < total:
        body = raw[index]
        if not body.strip() or body.strip() in ('---', '...'):
            index += 1
            continue
        indent = len(body) - len(body.lstrip())
        stripped = body.strip()
        match = re.match(r'^(.+?)\s*:\s*([>|])\s*$', stripped)
        if match:
            key = match.group(1)
            style = match.group(2)
            cursor = index + 1
            parts: list = []
            while cursor < total:
                nxt = raw[cursor]
                if not nxt.strip():
                    cursor += 1
                    continue
                nindent = len(nxt) - len(nxt.lstrip())
                if nindent <= indent:
                    break
                parts.append(nxt.strip())
                cursor += 1
            # YAML 的折叠/保留标量总是以换行结尾，与 PyYAML 保持一致。
            joined = ('\n' if style == '|' else ' ').join(parts) + '\n'
            out.append((indent, '%s:' % key.strip(), joined))
            index = cursor
            continue
        out.append((indent, stripped, None))
        index += 1
    return out


def _parse_block(tokens: list, i: int, indent: int):
    """解析缩进恰为 `indent` 的块 → `(值, 下一行下标)`。"""
    if tokens[i][1].startswith('-'):
        return _parse_seq(tokens, i, indent)
    return _parse_map(tokens, i, indent)


def _parse_map(tokens: list, i: int, indent: int):
    out: dict = {}
    total = len(tokens)
    while i < total:
        ind, body, folded = tokens[i]
        if ind != indent or body.startswith('-'):
            break
        key, value = _split_kv(body)
        if key is None:
            i += 1
            continue
        if folded is not None:
            out[key] = folded
            i += 1
        elif value == '':
            if i + 1 < total and tokens[i + 1][0] > indent:
                sub, i = _parse_block(tokens, i + 1, tokens[i + 1][0])
                out[key] = sub
            else:
                out[key] = None
                i += 1
        else:
            out[key] = _scalar(value)
            i += 1
    return out, i


def _parse_seq(tokens: list, i: int, indent: int):
    out: list = []
    total = len(tokens)
    while i < total:
        ind, body, folded = tokens[i]
        if ind != indent or not body.startswith('-'):
            break
        inner = body[1:].strip()
        i += 1
        if not inner:
            if i < total and tokens[i][0] > indent:
                sub, i = _parse_block(tokens, i, tokens[i][0])
                out.append(sub)
            else:
                out.append(None)
            continue
        key, value = _split_kv(inner)
        if key is None:
            out.append(_scalar(inner))
            continue
        # 列表项本身是映射的起始：`- key: value`，同项其余键缩进更深。
        item: dict = {}
        if folded is not None:
            item[key] = folded
        elif value == '':
            if i < total and tokens[i][0] > indent:
                sub, i = _parse_block(tokens, i, tokens[i][0])
                item[key] = sub
            else:
                item[key] = None
        else:
            item[key] = _scalar(value)
        while i < total and tokens[i][0] > indent and not tokens[i][1].startswith('-'):
            sub_ind, sub_body, sub_folded = tokens[i]
            k2, v2 = _split_kv(sub_body)
            if k2 is None:
                break
            if sub_folded is not None:
                item[k2] = sub_folded
                i += 1
            elif v2 == '':
                if i + 1 < total and tokens[i + 1][0] > sub_ind:
                    s, i = _parse_block(tokens, i + 1, tokens[i + 1][0])
                    item[k2] = s
                else:
                    item[k2] = None
                    i += 1
            else:
                item[k2] = _scalar(v2)
                i += 1
        out.append(item)
    return out, i


def _parse_minimal_yaml(path: str):
    """兜底解析：零依赖地正确解析 `platform_spec.yaml`。

    为什么不能将就：Windows / Linux runner 上未必装有 PyYAML，一旦这份兜底
    解析结果不完整，spec 会被**静默跳过**（表现为"规格中没有 windows 的条目"），
    平台编译宏 / 权限 / 图标全部不注入，构建期才炸，且日志里看不出是解析问题。
    `inject_platform_spec_selftest.py` 会断言它与 PyYAML 的结果一致。
    """
    tokens = _tokenize_yaml(path)
    if not tokens:
        return {}
    value, _ = _parse_block(tokens, 0, tokens[0][0])
    return value if isinstance(value, dict) else {}


def _read(path: str) -> str:
    with open(path, encoding='utf-8') as handle:
        return handle.read()


def _write(path: str, text: str) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(text)


def _write_bytes(path: str, blob: bytes) -> None:
    """二进制资源（ICO / PNG）必须用 `wb`，否则文本编码会破坏字节流。"""
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, 'wb') as handle:
        handle.write(blob)


def _resolve(root: str, relative: str) -> str:
    """把 spec 里的仓库相对路径解析成绝对路径。"""
    return relative if os.path.isabs(relative) else os.path.join(root, relative)


# ── 各 patch 实现 ────────────────────────────────────────────────────────

def _is_kotlin_dsl(path: str) -> bool:
    """`build.gradle.kts`（Kotlin DSL）还是 `build.gradle`（Groovy）。"""
    return str(path).endswith('.kts')


def patch_compile_sdk(root: str, step: dict) -> int:
    """把宿主 compileSdk 抬到插件要求的版本。

    必须覆盖 Flutter 模板的**全部**写法，否则会静默不生效：
      `compileSdkVersion flutter.compileSdkVersion`（Groovy 旧模板）
      `compileSdk = flutter.compileSdkVersion`（Kotlin DSL 新模板）
      `compileSdkVersion 35` / `compileSdk = 35`（直接写数字）
    """
    target = step.get('compile_sdk', 36)
    path = step['file']
    text = _read(path)
    if 'OGL_PLATFORM_SPEC compileSdk' in text:
        print('  [已存在] compileSdk（%s）' % path)
        return 0

    marker = ' // OGL_PLATFORM_SPEC compileSdk'
    updated = text
    # 逐个尝试模板写法；一旦命中就不再往下匹配。
    # ★ 必须**命中即停**：否则前一条把 `flutter.compileSdkVersion` 换成
    #   `compileSdk = 37` 后，后一条 `compileSdk\s*=\s*\d+` 会再次命中同一行，
    #   把标记追加两次（`... // OGL_PLATFORM_SPEC compileSdk // OGL_PLATFORM_SPEC
    #   compileSdk`）。
    for pattern, replacement in (
        (r'compileSdkVersion\s+flutter\.compileSdkVersion',
         'compileSdkVersion %d%s' % (target, marker)),
        (r'compileSdk\s*=\s*flutter\.compileSdkVersion',
         'compileSdk = %d%s' % (target, marker)),
        (r'compileSdkVersion\s+\d+',
         'compileSdkVersion %d%s' % (target, marker)),
        (r'compileSdk\s*=\s*\d+',
         'compileSdk = %d%s' % (target, marker)),
    ):
        if 'OGL_PLATFORM_SPEC compileSdk' in updated:
            break
        updated = re.sub(pattern, replacement, updated)

    if 'OGL_PLATFORM_SPEC compileSdk' not in updated:
        print('  [失败] %s 里找不到 compileSdk（模板写法可能又变了）' % path)
        return 1
    _write(path, updated)
    print('  [注入] %s → compileSdk %d（%s）'
          % (path, target, 'Kotlin DSL' if _is_kotlin_dsl(path) else 'Groovy'))
    return 0


def patch_core_library_desugaring(root: str, step: dict) -> int:
    """开启 core library desugaring（`flutter_local_notifications` 硬要求）。

    ⚠️ 三个坑（均为 CI 实证）：
    1. 只把开关打开**不够**，还必须在 `dependencies {}` 里声明
       `coreLibraryDesugaring` 依赖 —— AAR metadata 检查读的是依赖是否
       真的存在，否则报
       `Dependency ':flutter_local_notifications' requires core library
        desugaring to be enabled for :app`。
    2. Flutter 3.47.5 的模板已改为 **Kotlin DSL**（`build.gradle.kts`）。
       Groovy 写法（`coreLibraryDesugaringEnabled true`、单引号依赖）在
       `.kts` 里是**非法 Kotlin 语法**，必须按扩展名分派。
    3. 开关在 `android { compileOptions { } }` 里，依赖在**顶层**
       `dependencies { }` 里 —— 两者位置不同，要分别注入。
    """
    path = step['file']
    kotlin = _is_kotlin_dsl(path)
    # Kotlin: isCoreLibraryDesugaringEnabled = true / coreLibraryDesugaring("…")
    # Groovy: coreLibraryDesugaringEnabled true    / coreLibraryDesugaring '…'
    enable_line = ('isCoreLibraryDesugaringEnabled = true' if kotlin
                   else 'coreLibraryDesugaringEnabled true')
    dep_line = ('    coreLibraryDesugaring("%s")' % DESUGAR_DEP if kotlin
                else "    coreLibraryDesugaring '%s'" % DESUGAR_DEP)

    text = _read(path)
    if 'OGL_PLATFORM_SPEC desugaring' in text:
        print('  [已存在] desugaring（%s）' % path)
        return 0

    updated = text
    # ① 开关：模板里可能已经开了（那就只补标记），也可能压根没有（要插入）。
    switched = False
    for pattern in (r'isCoreLibraryDesugaringEnabled\s*=\s*true',
                    r'coreLibraryDesugaringEnabled\s*=\s*true',
                    r'coreLibraryDesugaringEnabled\s+true'):
        if re.search(pattern, updated):
            updated = re.sub(
                r'([^\n]*?true)', r'\1  // OGL_PLATFORM_SPEC desugaring',
                updated, count=1)
            switched = True
            break
    if not switched:
        if 'compileOptions' not in updated:
            print('  [失败] %s 里没有 compileOptions（模板已变？）' % path)
            return 1
        updated = updated.replace(
            'compileOptions {',
            'compileOptions {\n        %s  // OGL_PLATFORM_SPEC desugaring'
            % enable_line, 1)

    if 'OGL_PLATFORM_SPEC desugaring' not in updated:
        print('  [失败] desugaring 开关注入未命中：%s' % path)
        return 1

    # ② 依赖：必须在 dependencies 块里声明（AAR metadata 检查只看它）。
    if DESUGAR_DEP not in updated:
        if re.search(r'\n\s*dependencies\s*\{', updated):
            updated = re.sub(r'(\n\s*dependencies\s*\{\n)',
                             r'\1' + dep_line + '\n', updated, count=1)
            print('  [注入] dependencies 块内补 desugar 依赖')
        else:
            # ★ Flutter 3.47.5 的 Kotlin DSL 模板**根本没有**顶层
            #   `dependencies {}` 块（模板默认没有任何依赖要声明）。
            #   所以"往已有块里插"这条路走不通，必须自己建一个块。
            if not updated.endswith('\n'):
                updated += '\n'
            updated += '\ndependencies {\n%s\n}\n' % dep_line
            print('  [注入] 新建 dependencies 块并声明 desugar 依赖')

    _write(path, updated)
    print('  [注入] %s → desugaring 已开启并声明依赖（%s）'
          % (path, 'Kotlin DSL' if kotlin else 'Groovy'))
    return 0


def patch_android_permissions(root: str, step: dict) -> int:
    perms = step.get('permissions') or []
    path = step['file']
    text = _read(path)
    if 'OGL_PLATFORM_SPEC permissions' in text:
        print('  [已存在] Android 权限块')
        return 0
    lines = []
    for perm in perms:
        if ':' in perm:  # 属性而非权限
            lines.append('    <meta-data android:name="%s" android:value="true" />'
                         % perm.split(':', 1)[1])
        else:
            lines.append('    <uses-permission android:name="%s" />' % perm)
    block = PERMISSION_BLOCK.format(perms='\n'.join(lines) + '\n')
    marker = '    <application'
    if marker not in text:
        print('  [失败] %s 里找不到 <application>' % path)
        return 1
    updated = text.replace(marker, block + marker, 1)
    _write(path, updated)
    print('  [注入] %s → %d 项权限' % (path, len(perms)))
    return 0


def patch_write_vector_xml(root: str, step: dict) -> int:
    _write(step['file'], FOREGROUND_ICON)
    print('  [写入] %s（矢量前景）' % step['file'])
    return 0


def patch_write_adaptive_icon_xml(root: str, step: dict) -> int:
    _write(step['file'], ADAPTIVE_ICON)
    print('  [写入] %s（自适应图标）' % step['file'])
    return 0


def patch_set_app_label(root: str, step: dict) -> int:
    path = step['file']
    value = step.get('value', 'OGL')
    text = _read(path)
    updated, count = re.subn(r'android:label="[^"]*"',
                             'android:label="%s"' % value, text, count=1)
    if not count:
        print('  [跳过] %s 里找不到 android:label' % path)
        return 0
    _write(path, updated)
    print('  [注入] %s → label=%s' % (path, value))
    return 0


def patch_add_compile_definitions(root: str, step: dict) -> int:
    path = step['file']
    defs = step.get('definitions') or []
    text = _read(path)
    if 'OGL_PLATFORM_SPEC' in text:
        print('  [已存在] 编译宏')
        return 0
    line = 'add_compile_definitions(%s)  # OGL_PLATFORM_SPEC coroutine\n' % ' '.join(defs)
    lines = text.splitlines(keepends=True)
    insert_at = next((i for i, l in enumerate(lines)
                      if l.strip() and not l.strip().startswith('#')), 0)
    lines.insert(insert_at, line)
    _write(path, ''.join(lines))
    if 'OGL_PLATFORM_SPEC' not in _read(path):
        print('  [失败] 宏注入后未生效：%s' % path)
        return 1
    print('  [注入] %s → %d 个编译宏' % (path, len(defs)))
    return 0


def patch_add_entitlement(root: str, step: dict) -> int:
    path = step['file']
    if not os.path.isfile(path):
        print('  [跳过] %s 不存在（非该平台构建）' % path)
        return 0
    key = step.get('key')
    text = _read(path)
    if key and key in text:
        print('  [已存在] %s' % key)
        return 0
    if '</dict>' not in text:
        print('  [跳过] %s 里没有 </dict>' % path)
        return 0
    _write(path, text.replace('</dict>', '\t<key>%s</key>\n\t<true/>\n</dict>' % key))
    print('  [注入] %s → %s' % (path, key))
    return 0


def patch_write_ico(root: str, step: dict) -> int:
    import desktop_icon  # noqa: PLC0415 - 同目录模块

    size = int(step.get('size', 256))
    rgba = desktop_icon.render_rgba(_resolve(root, step.get('source')), size)
    png = desktop_icon.encode_png(rgba, size)
    _write_bytes(step['file'], desktop_icon.encode_ico(png, size))
    print('  [写入] %s（ICO %d）' % (step['file'], size))
    return 0


def patch_write_png(root: str, step: dict) -> int:
    import desktop_icon  # noqa: PLC0415 - 同目录模块

    size = int(step.get('size', 2048))
    rgba = desktop_icon.render_rgba(_resolve(root, step.get('source')), size)
    _write_bytes(step['file'], desktop_icon.encode_png(rgba, size))
    print('  [写入] %s（PNG %d）' % (step['file'], size))
    return 0


PATCHES = {
    'compile_sdk': patch_compile_sdk,
    'core_library_desugaring': patch_core_library_desugaring,
    'android_permissions': patch_android_permissions,
    'write_vector_xml': patch_write_vector_xml,
    'write_adaptive_icon_xml': patch_write_adaptive_icon_xml,
    'set_app_label': patch_set_app_label,
    'add_compile_definitions': patch_add_compile_definitions,
    'add_entitlement': patch_add_entitlement,
    'write_ico': patch_write_ico,
    'write_png': patch_write_png,
}


def main() -> int:
    ap = argparse.ArgumentParser(description='按 platform_spec.yaml 注入平台私有文件')
    ap.add_argument('--target', help='目标平台（android / windows / linux / macos）')
    ap.add_argument('--job', help='只跑某个 job id')
    ap.add_argument('--root', default=ROOT)
    ap.add_argument('--spec', default=SPEC)
    ap.add_argument('--list', action='store_true', help='只列规格')
    args = ap.parse_args()

    if not os.path.isfile(args.spec):
        sys.stderr.write('缺少平台规格：%s\n' % args.spec)
        return 1

    sys.path.insert(0, os.path.dirname(os.path.abspath(args.spec)))
    data = _load_spec(args.spec)
    specs = data.get('specs') or []
    if not specs:
        sys.stderr.write('规格为空或解析失败：%s\n' % args.spec)
        return 1

    if args.list or not args.target:
        for item in specs:
            print('%-10s %-28s %s' % (item.get('target'), item.get('id'),
                                      str(item.get('why', '')).strip()[:60]))
        return 0

    failed = 0
    ran = 0
    for item in specs:
        if item.get('target') != args.target:
            continue
        if args.job and item.get('id') != args.job and item.get('job') != args.job:
            continue
        ran += 1
        why = str(item.get('why', '')).strip()
        if not why:
            sys.stderr.write('[拒绝] %s 缺少 why —— 写不了 Dart 必须写清理由\n'
                             % item.get('id'))
            failed += 1
            continue
        print('== %s（%s）' % (item.get('id'), why.splitlines()[0][:70]))
        for step in (item.get('steps') or []):
            if 'file' not in step:
                continue
            handler = PATCHES.get(step.get('patch'))
            if handler is None:
                sys.stderr.write('  [跳过] 未知 patch：%s\n' % step.get('patch'))
                continue
            # handler 一律接收**绝对路径**（spec 里写的是相对仓库根的路径）。
            resolved = os.path.join(args.root, step['file'])
            if not os.path.exists(resolved) and step.get('patch') not in CREATE_PATCHES:
                # ★ 这里必须**报错退出**，不能静默跳过。
                #   正在构建 --target 指定的平台，就说明该平台的文件一定存在；
                #   找不到只有一种解释：**spec 与 Flutter 模板脱节**（例如模板
                #   从 build.gradle 迁到了 build.gradle.kts）。
                #   曾经就是这里静默跳过，导致 compileSdk 没抬、desugaring
                #   没开，Android 五条腿全红，而日志里看不出是注入问题。
                sys.stderr.write(
                    '  [失败] %s 不存在（正在构建 %s 平台却缺目标文件）：'
                    '多半是 Flutter 模板改名/迁移了，请同步 tool/platform_spec.yaml\n'
                    % (step['file'], args.target))
                failed += 1
                continue
            step = dict(step, file=resolved)
            failed += handler(args.root, step)

    if not ran:
        # ★ 同样必须报错：`--target X` 却一条 spec 都没匹配上，说明 spec 里
        #   没有 X 的条目 —— 这正是"Windows 两条腿全红且日志只显示一行
        #   '规格中没有 windows 的条目（跳过）'"的成因。
        sys.stderr.write(
            '[失败] 规格里没有 %s 的条目：请检查 tool/platform_spec.yaml '
            '是否被解析器漏读（本文件依赖零依赖兜底解析器）\n' % args.target)
        failed += 1
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())