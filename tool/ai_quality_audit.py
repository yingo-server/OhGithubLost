#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 每小时质量审计（Agnes，逐文件审查 lib/ 代码质量）。

设计：
  - 逐个 `lib/**/*.dart` 文件调用 Agnes（高智能 `agnes-2.5-flash`）；
  - **严格限速**：默认 5 rpm（API 上限约 10，取一半留余量，避免 429）；
  - 输出 **TXT 报告**：每文件一节（结论 + 具体问题 + 建议），末尾汇总统计；
  - 报告打印到 stdout（CI 可见），同时写入 `build/quality_audit.txt`（供发布）。

调用约定与翻译工具 / ai_audit 一致：
  ENDPOINT https://apihub.agnes-ai.com/v1/chat/completions
  密钥：环境变量 `AGNES_API_KEY`（缺失则跳过并显式标注）。
"""
from __future__ import annotations

import glob
import json
import os
import sys
import time
import urllib.request

ENDPOINT = 'https://apihub.agnes-ai.com/v1/chat/completions'
MODEL = os.environ.get('OGL_AI_MODEL', 'agnes-2.5-flash')
# API 上限约 10 rpm；取 5，留余量（默认，可用 OGL_QA_RPM 覆盖）。
RPM = int(os.environ.get('OGL_QA_RPM', '5'))
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
MAX_CHARS = 8000
OUT_REL = os.path.join('build', 'quality_audit.txt')


def call_ai(api_key: str, prompt: str) -> str:
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
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode('utf-8'))
    return data['choices'][0]['message']['content']


class _Limiter:
    """按 rpm 限速：每次调用之间至少间隔 60/rpm 秒（并发安全不需要，串行即可）。"""

    def __init__(self, rpm: int):
        self.interval = 60.0 / max(1, rpm)
        self.last = 0.0

    def wait(self) -> None:
        now = time.monotonic()
        gap = self.interval - (now - self.last)
        if gap > 0:
            time.sleep(gap)
        self.last = time.monotonic()


def _prompt_for(rel: str, text: str) -> str:
    return (
        '你是 OGL（OhGithubLost，Flutter GitHub 客户端）的资深代码评审。'
        '请审查下面这个 Dart 文件。**判定纪律（严格遵守，宁可漏报不可误报）**：\n'
        '1. 只报告**能指明行号/符号、并能用代码证实**的问题；没有确凿依据的'
        '   "风格建议"一律不提；\n'
        '2. **禁止臆测**：看不到调用点/数据流就断言"可能竞态/可能泄漏"，'
        '   属于臆测，不算问题；除非代码里有**可指出的**未 await、未释放、'
        '   可变全局共享等具体反模式；\n'
        '3. 首行判定：**[FAIL]**=存在必然导致错误/崩溃/安全漏洞的确凿问题；'
        '   **[WARN]**=存在**可证实**的改进点（有行号依据）；'
        '   其余一律 **[PASS]**（无确凿问题不标 WARN，避免假阳性）。\n'
        '4. 若文件只是声明/常量/工具类且无逻辑，直接 [PASS]。\n'
        '审查维度（只在**可证实**时报告）：\n'
        '1) 正确性 / 空安全 / 异步竞态（有具体行号的未 await / 可空解引用）；\n'
        '2) 安全性（密钥硬编码、路径穿越、注入、外部链接未校验 scheme）；\n'
        '3) 性能反模式（无谓重建、宽 MediaQuery.of、整列同步构建——可证实才报）；\n'
        '4) 四层架构（surface→domain→base→kernel，本文件是否**明确**违规向上 import）；\n'
        '5) i18n（界面文案硬编码中文且**不在注释/日志**里，可证实才报）。\n'
        '输出格式：第一行 **[PASS]** / **[WARN]** / **[FAIL]**；'
        '随后每行一个**可证实**的问题，格式 `- <行号> <问题>`；'
        '没有问题就只输出首行判定。\n'
        '---------- 文件：%s ----------\n%s' % (rel, text)
    )


def main() -> int:
    key = os.environ.get('AGNES_API_KEY', '').strip()
    if not key:
        print('AGNES_API_KEY 未设置 —— 跳过质量审计（显式标注）')
        return 2

    files = sorted(glob.glob(os.path.join(REPO, 'lib', '**', '*.dart'), recursive=True))
    if not files:
        print('lib/ 下没有 Dart 文件')
        return 2

    limiter = _Limiter(RPM)
    sections = []
    passed = warned = failed = errors = 0
    started = time.time()

    for i, path in enumerate(files, 1):
        rel = os.path.relpath(path, REPO)
        text = open(path, encoding='utf-8', errors='replace').read()
        if len(text) > MAX_CHARS:
            text = text[:MAX_CHARS] + '\n...[截断，仅评审前 %d 字符]' % MAX_CHARS
        limiter.wait()
        try:
            verdict = call_ai(key, _prompt_for(rel, text))
        except Exception as exc:  # noqa: BLE001
            verdict = '[FAIL] 审查调用失败：%s' % exc
            errors += 1
        head = verdict.strip().splitlines()[0] if verdict.strip() else ''
        if head.startswith('[PASS]'):
            passed += 1
        elif head.startswith('[WARN]'):
            warned += 1
        elif head.startswith('[FAIL]'):
            failed += 1
        else:
            errors += 1
        sections.append('### %s\n%s\n' % (rel, verdict.strip()))
        print('[%d/%d] %s :: %s' % (i, len(files), rel, head[:70]), flush=True)

    elapsed = int(time.time() - started)
    header = (
        'OGL · 每小时质量审计报告（Agnes %s · 逐文件审查 lib/）\n'
        '生成时间：%s\n'
        '文件数：%d　PASS：%d　WARN：%d　FAIL：%d　调用失败：%d　耗时：%ds\n'
        '限速说明：%d rpm（API 上限约 10，取一半留余量）\n'
        '%s\n' % (
            MODEL, time.strftime('%Y-%m-%d %H:%M:%S %z'),
            len(files), passed, warned, failed, errors, elapsed,
            RPM, '=' * 40,
        )
    )
    summary = (
        '\n%s\n汇总：%d 个文件，PASS %d / WARN %d / FAIL %d / 调用失败 %d\n'
        '（PASS/WARN/FAIL 以各文件首行标记为准）\n' % ('=' * 40, len(files), passed, warned, failed, errors)
    )
    report = header + '\n\n'.join(sections) + summary

    out = os.path.join(REPO, OUT_REL)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as handle:
        handle.write(report)
    print('REPORT=%s' % OUT_REL)
    print('SUMMARY=files:%d pass:%d warn:%d fail:%d errors:%d' % (
        len(files), passed, warned, failed, errors))
    # 存在 FAIL 级问题 → 非零退出（CI 可见），但报告仍已生成。
    return 1 if (failed + errors > 0) else 0


if __name__ == '__main__':
    raise SystemExit(main())
