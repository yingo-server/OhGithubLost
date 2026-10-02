/// L1 底座级 · **日志目录候选链**（"日志到底写到哪儿"的唯一答案处）。
///
/// 用户的要求是明确的：**始终保存到 `sdcard/logging`**（即
/// `/storage/emulated/0/logging`），其它平台同理给一个"看得见"的位置。
///
/// 但 Android 的存储权限是分层的：
/// - Android ≤ 9：`WRITE_EXTERNAL_STORAGE` 授权后可直接写 `/storage/emulated/0/logging`；
/// - Android 10：分区存储默认开启，需 `requestLegacyExternalStorage`（旧式）或应用外部目录；
/// - Android 11+：**根目录不可写**，除非用户在系统设置里授予"所有文件访问"
///   （`MANAGE_EXTERNAL_STORAGE`）。本应用**不弹**这个重型权限，
///   而是：先试 sdcard → 失败就退到应用外部目录（无需任何权限、文件管理器可见）→
///   再退到应用文档/支持目录；**并把"实际写到哪 + 为什么没写到 sdcard"如实告诉用户**
///   （关于页可见）。
///
/// 顺序即优先级：越靠前越"用户看得见"。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

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

  // ① 用户点名：sdcard/logging（Android 上需要"所有文件访问"才写得动；
  //     其它平台没有这个路径，自然不会命中）。
  add('/storage/emulated/0/logging');

  // ② Android 应用外部目录：**无需任何权限**、文件管理器可见
  //     （/storage/emulated/0/Android/data/<pkg>/files/logging）。
  if (Platform.isAndroid) {
    try {
      final Directory? ext = await getExternalStorageDirectory();
      add(ext == null ? null : '${ext.path}/logging');
    } catch (_) {
      // 某些定制 ROM 会抛；忽略，继续往下退。
    }
  }

  // ③ 应用文档目录（桌面平台是 ~/Documents，用户看得见）。
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    add('${docs.path}/logging');
  } catch (_) {
    // 忽略。
  }

  // ④ 应用支持目录：一定可写，保底。
  try {
    final Directory support = await getApplicationSupportDirectory();
    add('${support.path}/logging');
  } catch (_) {
    // 忽略。
  }

  return out;
}