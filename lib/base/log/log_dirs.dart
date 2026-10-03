/// L1 底座级 · **日志目录候选链**（"日志到底写到哪儿"的唯一答案处）。
///
/// 日志统一写入应用根目录下的 `logging/`（默认 `<sdcard>/ogl/logging`，
/// 平台不可写时自动退到应用可见目录，见 `disk/app_dirs.dart`）。
///
/// 顺序即优先级：越靠前越"用户看得见"。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../disk/app_dirs.dart';

/// 解析日志目录候选清单（去重、规整为正斜杠路径）。
///
/// 返回的**第一个**可写目录会被 `OgLLogFile` 采用。
Future<List<String>> ogLLogDirectoryCandidates() async {
  final List<String> out = <String>[];
  void add(String? path) {
    if (path == null || path.isEmpty) {
      return;
    }
    final String normalized = path.replaceAll(r'\', '/');
    if (!out.contains(normalized)) {
      out.add(normalized);
    }
  }

  // ① 应用根目录下的 logging（默认 <sdcard>/ogl/logging）。
  try {
    add(await OgLAppDirs.logging());
  } catch (_) {
    // 解析失败：继续走后面的兜底候选。
  }

  // ② 应用文档目录（桌面平台是 ~/Documents，用户看得见）。
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    add('${docs.path}/logging');
  } catch (_) {
    // 忽略。
  }

  // ③ 应用支持目录：一定可写，保底。
  try {
    final Directory support = await getApplicationSupportDirectory();
    add('${support.path}/logging');
  } catch (_) {
    // 忽略。
  }

  return out;
}