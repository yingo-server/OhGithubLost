/// L3 展示级 · **启动期权限自检**（每次启动都跑，不只是首次引导）。
///
/// ## 为什么要有它
/// 引导页只在**首次**请求权限，之后再也不看。于是出现这类真实故障：
/// 用户在系统设置里关掉了「存储 / 通知」，应用能开、能刷，但**日志写不进外部目录、
/// 下载完成提示永远不出现**——没人告诉他是权限问题，只会以为“应用坏了”。
///
/// 本模块在每次启动时**实测**一遍（不是读缓存状态）：
/// - 存储：走真实写入探针（`storageProbe`）——「授权了但写不动」也会被如实反映；
/// - 通知：向系统查询当前是否真的可发（Android 13+ 的运行时权限）。
///
/// ## 纪律
/// - **不弹窗、不打断启动**：只复核，不重新请求（重新请求交给引导页 / 设置页）；
/// - **不静默**：缺什么、影响什么、怎么修，写进诊断日志，
///   并经通知中心以**带事件码**的告警呈现（warn 级 → 横幅）；
/// - **永不抛**：自检自身失败也要留痕（`OGL-PERM-000`），绝不因此拖垮启动。
library;

import 'package:flutter/foundation.dart';

import '../../kernel/diagnostics.dart';
import '../i18n/og_l_i18n.dart';
import 'permissions.dart';

/// 取 `shell` 分片文案。
String _t(String key) => OgLI18n.instance.t('shell', key);

/// 自检自身失败（拿不到权限清单）。
const String kOgLPermSelfTestFailed = 'OGL-PERM-000';

/// 存储 / 文件访问未就绪。
const String kOgLPermStorageMissing = 'OGL-PERM-001';

/// 通知未就绪。
const String kOgLPermNotifyMissing = 'OGL-PERM-002';

/// 一次自检的结果。
@immutable
class OgLPermissionSelfTestReport {
  /// 创建结果。
  const OgLPermissionSelfTestReport({
    required this.platform,
    required this.infos,
    required this.duration,
  });

  /// 平台标签（如 `Android`）。
  final String platform;

  /// 本次实测到的权限清单（含状态）。
  final List<OgLPermissionInfo> infos;

  /// 自检耗时。
  final Duration duration;

  /// 需要用户处理的条目（也就是会打扰用户的那几条）。
  List<OgLPermissionInfo> get actionable => <OgLPermissionInfo>[
        for (final OgLPermissionInfo info in infos)
          if (info.actionable) info,
      ];

  /// 是否全部就绪。
  bool get allReady => actionable.isEmpty;

  /// 就绪条目数。
  int get readyCount =>
      infos.where((OgLPermissionInfo info) => info.ready).length;

  /// 序列化（启动报告 / 关于页诊断用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'platform': platform,
        'ms': duration.inMicroseconds / 1000,
        'allReady': allReady,
        'items': <Map<String, Object?>>[
          for (final OgLPermissionInfo info in infos)
            <String, Object?>{
              'permission': info.permission.name,
              'status': info.status.name,
              if (info.actionable) 'code': codeOf(info.permission),
            },
        ],
      };

  /// 最近一次自检结果（关于页 / 设置页展示用）。
  static OgLPermissionSelfTestReport? last;

  /// 权限 → 稳定事件码（可检索、可写进 issue）。
  static String codeOf(OgLPermission permission) =>
      permission == OgLPermission.storage
          ? kOgLPermStorageMissing
          : kOgLPermNotifyMissing;
}

/// 跑一次启动期权限自检并汇报结果。
///
/// [diagnostics] 为内核诊断中枢：**问题条目以 warn 级 + 事件码上报**，
/// 经 `OgLDiagnosticsNoticeSink` 进通知中心（用户看得见），
/// 同时进内存日志与落盘日志（排查时看得到）。
///
/// [gateway] 仅测试注入用；正式启动不传，由平台自动选择。
Future<OgLPermissionSelfTestReport> ogLRunPermissionSelfTest({
  required KernelDiagnostics diagnostics,
  Future<bool> Function()? storageProbe,
  OgLPermissionGateway? gateway,
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  final OgLPermissionGateway use =
      gateway ?? ogLPermissionGateway(storageProbe: storageProbe);
  List<OgLPermissionInfo> infos;
  try {
    infos = await use.describe();
  } catch (error) {
    stopwatch.stop();
    diagnostics.error(
      'PERM',
      '权限自检失败（无法读取当前权限清单）：$error',
      code: kOgLPermSelfTestFailed,
      data: <String, Object?>{
        'platform': use.platformLabel,
        'error': '$error',
      },
    );
    final OgLPermissionSelfTestReport report = OgLPermissionSelfTestReport(
      platform: use.platformLabel,
      infos: const <OgLPermissionInfo>[],
      duration: stopwatch.elapsed,
    );
    OgLPermissionSelfTestReport.last = report;
    return report;
  }
  stopwatch.stop();

  for (final OgLPermissionInfo info in infos) {
    if (!info.actionable) {
      // 就绪项只留日志（info 级不进通知中心，避免打扰）。
      diagnostics.info(
        'PERM',
        '${info.permission.name}=${info.status.name}',
        data: <String, Object?>{
          'platform': use.platformLabel,
          'status': info.status.name,
        },
      );
      continue;
    }
    diagnostics.warn(
      'PERM',
      _problemMessage(info),
      code: OgLPermissionSelfTestReport.codeOf(info.permission),
      data: <String, Object?>{
        'platform': use.platformLabel,
        'permission': info.permission.name,
        'status': info.status.name,
      },
    );
  }

  final OgLPermissionSelfTestReport report = OgLPermissionSelfTestReport(
    platform: use.platformLabel,
    infos: infos,
    duration: stopwatch.elapsed,
  );
  OgLPermissionSelfTestReport.last = report;
  diagnostics.info(
    'PERM',
    report.allReady
        ? '权限自检通过：${report.readyCount}/${infos.length} 项就绪'
        : '权限自检：${report.actionable.length} 项需要处理'
            '（${report.actionable.map((OgLPermissionInfo i) => i.permission.name).join('、')}）',
    data: report.toJson(),
  );
  return report;
}

/// 问题条目的用户可读说明（界面文案 → `shell` 分片，15 语言）。
String _problemMessage(OgLPermissionInfo info) {
  switch (info.permission) {
    case OgLPermission.storage:
      return _t('permStorageProblem');
    case OgLPermission.notifications:
      return _t('permNotifyProblem');
  }
}
