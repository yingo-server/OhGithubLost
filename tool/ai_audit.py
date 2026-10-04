#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · AI 审计（Agnes，由 CI 调用）。

对「正则规则覆盖不到」的盲区做高智能度复核，与规则审计互补：

  - 架构分层：依赖方向是否仍然可辩护（含白名单外的新跨越）；
  - 安全    ：密钥 / 临时文件 / 注入面 / 外部链接处理；
  - i18n    ：新增界面文案是否全部走分片（摘要内可见的硬编码中文）；
  - 性能    ：明显反模式是否回归（正则漏掉的交叉场景）；
  - 变更记录：CHANGELOG 与 release_notes 是否与代码面一致（有无夸大/遗漏）。

调用约定（与翻译工具一致）：
  ENDPOINT https://apihub.agnes-ai.com/v1/chat/completions
  高智能模型 `agnes-2.5-flash`（评审要"想"，不是"查表"）；
  常规 `agnes-3.0-flash`。
密钥从环境变量 `AGNES_API_KEY` 读取；缺失则跳过并显式标注。
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request

ENDPOINT = 'https://apihub.agnes-ai.com/v1/chat/completions'
MODEL = os.environ.get('OGL_AI_MODEL', 'agnes-2.5-flash')
BASE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(BASE, '..'))


def _summarise(paths, max_chars=6000):
    """抓关键文件头部摘要（避免把整仓塞进 prompt，同时保留足够的审查面）。"""
    parts = []
    for rel in paths:
        full = os.path.join(REPO, rel)
        if not os.path.isfile(full):
            parts.append('## %s (缺失)' % rel)
            continue
        text = open(full, encoding='utf-8', errors='replace').read()
        parts.append('## %s\n%s' % (rel, text[:max_chars]))
    return '\n\n'.join(parts)


def _walk_dart(limit=120):
    """收集 lib/ 下 Dart 文件路径（供跨面扫描），限制数量防 prompt 爆炸。"""
    out = []
    for root, _dirs, files in os.walk(os.path.join(REPO, 'lib')):
        for name in sorted(files):
            if name.endswith('.dart'):
                rel = os.path.relpath(os.path.join(root, name), REPO)
                out.append(rel)
                if len(out) >= limit:
                    return out
    return out


def call_ai(api_key, prompt):
    body = json.dumps({
        'model': MODEL,
        'messages': [{'role': 'user', 'content': prompt}],
        'temperature': 0.2,
    }).encode('utf-8')
    req = urllib.request.Request(
        ENDPOINT, data=body, method='POST',
        headers={'Content-Type': 'application/json',
                 'Authorization': 'Bearer ' + api_key},
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode('utf-8'))
    return data['choices'][0]['message']['content']


def main(argv):
    key = os.environ.get('AGNES_API_KEY', '').strip()
    if not key:
        print('AGNES_API_KEY 未设置 —— 跳过 AI 审计（显式标注，不视为失败）')
        return 0

    # 覆盖面：核心安全/性能模块全文 + 关键页面 + 变更记录 + 依赖 + 全量文件清单。
    files = [
        'lib/kernel/kernel.dart', 'lib/base/disk/disk_cache.dart',
        'lib/base/disk/platform_io.dart', 'lib/base/net/net_dns.dart',
        'lib/base/net/net_mirror.dart', 'lib/surface/pages/settings_page.dart',
        'lib/surface/pages/repo_page.dart', 'lib/surface/widgets/readme_view.dart',
        'lib/surface/app/desktop_window.dart', 'lib/surface/util/link_opener.dart',
        'CHANGELOG.md', 'release_notes/v6.0.0.md', 'pubspec.yaml',
    ]
    context = _summarise(files)
    dart_list = '\n'.join(_walk_dart())
    prompt = (
        '你是 OGL（OhGithubLost）项目的资深代码评审。请阅读以下文件摘要，'
        '逐项给出**可执行结论**（通过 / 改进 / 问题），不要泛泛而谈：\n'
        '1) 四层架构依赖方向是否仍然成立（surface→domain→base→kernel）；\n'
        '2) 是否存在明显的安全 / 密钥 / 临时文件 / 外链处理风险；\n'
        '3) i18n 是否有界面文案漏走分片（摘要内可见的硬编码中文）；\n'
        '4) 是否有明显性能反模式回归（正则漏掉的交叉场景）；\n'
        '5) CHANGELOG / release_notes 是否与代码面一致（有无夸大或遗漏）。\n'
        '6) 依赖（pubspec.yaml）是否有明显不必要的增删或版本风险。\n'
        '最后给出总评（PASS / WARN / FAIL），并列出"建议补进规则审计"的具体项。\n'
        '---------- 文件摘要 ----------\n' + context +
        '\n---------- lib/ 文件清单 ----------\n' + dart_list
    )
    try:
        verdict = call_ai(key, prompt)
    except Exception as exc:
        print('AI 审计调用失败：%s' % exc)
        return 2  # 调用失败 = 显式失败，别静默
    print(verdict)
    if '\nFAIL' in verdict or verdict.strip().startswith('FAIL'):
        print('::error title=AI审计::发现 FAIL 级问题，详见上方输出')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
