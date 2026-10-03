/// L3 展示级 · 仓库条目路径规则（新建 / 重命名共用）。
///
/// ## 用户规则（必须严格遵守）
/// - **禁止中文与全角字符**：GitHub 路径本身接受，但本应用后续若要落盘 /
///   转译，中文与全角字符极易出错，因此**在入口直接禁止**；
/// - **禁止特殊字符**：只允许 `A-Z a-z 0-9 . _ -` 与路径分隔符 `/`；
///   其余（空格、`<>:"|?*#%\` 与控制字符）一律拒绝；
/// - **目录用 `.gitkeep` 占位**：Git 不跟踪空目录，所以"添加路径" =
///   在该目录下创建 `.gitkeep`；
/// - **新建文件必须有内容**：空文件没有意义（`.gitkeep` 占位例外）。
library;

/// `.gitkeep` 文件名（目录占位）。
const String kOgLGitKeepName = '.gitkeep';

/// Windows 保留名（大小写不敏感；这些名字在 Windows 上无法落盘）。
const Set<String> _kReservedNames = <String>{
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// 中文 / 全角 / 其他不可见字符（含 CJK、全角标点）。
final RegExp _kCjk = RegExp(r'[\u2E80-\u9FFF\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFFEF]');

/// 单个路径段允许的字符（不含 `/`）。
final RegExp _kAllowedSegment = RegExp(r'^[A-Za-z0-9._-]+$');

/// 控制字符。
final RegExp _kControl = RegExp(r'[\x00-\x1F\x7F]');

/// 是否为目录占位文件。
bool ogLIsGitKeep(String path) {
  final List<String> parts = path.split('/');
  return parts.isNotEmpty && parts.last == kOgLGitKeepName;
}

/// 目录 → 占位文件路径（`docs/` → `docs/.gitkeep`；根目录 → `.gitkeep`）。
String ogLGitKeepPathFor(String directory) {
  final String trimmed = directory.replaceAll(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? kOgLGitKeepName : '$trimmed/$kOgLGitKeepName';
}

/// 校验"新建条目"的路径。
///
/// [raw] 以 `/` 结尾表示**建目录**（会用 `.gitkeep` 占位）。
/// 返回 `null` 表示通过；否则返回**给用户看的**原因（可直接展示）。
String? ogLValidateRepoEntryPath(String raw, {required bool directory}) {
  final String input = raw.trim();
  if (input.isEmpty) {
    return directory ? '请填写目录路径（如 docs/api/）' : '请填写文件路径（如 src/main.dart）';
  }
  if (_kControl.hasMatch(input)) {
    return '路径不能包含控制字符';
  }
  if (_kCjk.hasMatch(input)) {
    return '路径不能包含中文或全角字符（请改用英文）';
  }
  if (input.contains(r'\')) {
    return '请使用 / 作为路径分隔符，不要用 \\';
  }
  if (input.startsWith('/')) {
    return '路径不能以 / 开头';
  }
  if (input.contains('//')) {
    return '路径中不能出现连续的两个 /';
  }
  final bool trailingSlash = input.endsWith('/');
  final List<String> segments = input
      .split('/')
      .where((String s) => s.isNotEmpty)
      .toList();
  if (segments.isEmpty) {
    return '路径无效';
  }
  if (directory && !trailingSlash) {
    // 目录必须以 `/` 结尾，避免与"建文件"混淆。
    return '创建目录时路径需以 / 结尾（如 docs/api/）';
  }
  if (!directory && trailingSlash) {
    return '创建文件时路径不能以 / 结尾';
  }
  for (final String segment in segments) {
    final String? error = _validateSegment(segment, directory: directory);
    if (error != null) {
      return error;
    }
  }
  return null;
}

String? _validateSegment(String segment, {required bool directory}) {
  if (segment == '.' || segment == '..') {
    return '路径中不能包含 . 或 ..';
  }
  if (segment.length > 100) {
    return '单级名称不能超过 100 个字符（当前 ${segment.length}）';
  }
  if (segment.endsWith('.') || segment.endsWith(' ')) {
    return '名称不能以点或空格结尾（Windows 上无法落盘）';
  }
  if (segment.startsWith(' ') || segment.contains(' ')) {
    return '名称不能包含空格';
  }
  if (!_kAllowedSegment.hasMatch(segment)) {
    return '名称只能使用英文字母、数字与 . _ -（不能含特殊字符）';
  }
  final String stem = segment.contains('.')
      ? segment.substring(0, segment.indexOf('.'))
      : segment;
  if (_kReservedNames.contains(stem.toLowerCase())) {
    return '“$segment”是 Windows 保留名，无法落盘';
  }
  // 目录不需要扩展名约束；文件需有扩展名（.gitkeep / .gitignore 等点文件除外）。
  if (!directory && !segment.startsWith('.')) {
    // 仅提示，不强制（有些仓库确实存在无扩展名文件），因此这里放行。
  }
  return null;
}

/// 文件内容校验（用户规则：**不允许空文件**）。
///
/// 返回 `null` 表示通过。`.gitkeep` 允许为空（它只是目录占位）。
String? ogLValidateFileContent(String path, String content) {
  if (ogLIsGitKeep(path)) {
    return null;
  }
  if (content.trim().isEmpty) {
    return '文件内容不能为空（请至少写入一行）';
  }
  return null;
}
