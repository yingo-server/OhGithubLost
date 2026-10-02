/// L3 展示级 · 代码语法高亮（轻量、零外部依赖）。
///
/// ## 为什么自己写
/// 语法高亮插件普遍要求引入 `highlight` / `flutter_highlight` 等依赖，
/// 而本仓库的依赖纪律是"只留真的被 import 到、且不拖垮构建链的包"。
/// 需求只要求"代码文件有高亮"，不是 IDE 级精确 —— 一个纯 Dart 的
/// 词法扫描器足够：识别 **注释 / 字符串 / 数字 / 关键词 / 类型名**。
///
/// ## 两条纪律
/// 1. 扫描器是**纯函数**（`source + language → tokens`），可离线单测；
/// 2. **绝不修改原文本**：所有 token 首尾相接必须还原成原文
///    （否则用户复制代码会得到被"吃掉"的内容）。
library;
import 'package:flutter/material.dart';

/// 高亮字符上限：超过则**退回纯文本**渲染。
///
/// 核心理由（极端条件）：高亮会为每个片段生成 `TextSpan`。对超大源码，
/// 片段数与内存占用会线性膨胀；低端设备上表现为长卡顿甚至 OOM。
/// 仓库代码查看器虽已拦截 >1MB 文件，但这里仍加一道**独立护栏**，
/// 保证 `CodeView` 被复用到任何位置都不会因输入变大而失控。
const int kOgLCodeHighlightMaxChars = 200000;

/// 行号渲染上限：超过则不再显示行号。
///
/// 行号是按行生成的 `Text` 组件，十万行会直接构造十万个组件——
/// 这是"能跑但会在极端输入下崩"的典型隐患，故设上限。
const int kOgLCodeGutterMaxLines = 3000;

/// token 类别。
enum OgLCodeTokenKind {
  /// 普通文本。
  plain,

  /// 关键词。
  keyword,

  /// 类型 / 内置名。
  type,

  /// 字符串字面量。
  string,

  /// 注释。
  comment,

  /// 数字字面量。
  number,
}

/// 一个词法片段。
@immutable
class OgLCodeToken {
  /// 创建片段。
  const OgLCodeToken(this.kind, this.text);

  /// 类别。
  final OgLCodeTokenKind kind;

  /// 原文（不可为空）。
  final String text;

  @override
  String toString() => '${kind.name}(${text.length})';
}

// ─────────────────────────────────────────────────────────────────────────────
// 语言识别
// ─────────────────────────────────────────────────────────────────────────────

/// 由文件路径推断语言标识（小写；未知返回空串）。
String ogLDetectLanguage(String path) {
  final int slash = path.lastIndexOf('/');
  final String base =
      (slash >= 0 ? path.substring(slash + 1) : path).toLowerCase();
  final int dot = base.lastIndexOf('.');
  final String ext = dot <= 0 ? '' : base.substring(dot + 1);
  switch (ext) {
    case 'dart':
      return 'dart';
    case 'js':
    case 'mjs':
    case 'cjs':
      return 'javascript';
    case 'jsx':
      return 'jsx';
    case 'ts':
      return 'typescript';
    case 'tsx':
      return 'tsx';
    case 'py':
      return 'python';
    case 'java':
      return 'java';
    case 'kt':
    case 'kts':
      return 'kotlin';
    case 'go':
      return 'go';
    case 'rs':
      return 'rust';
    case 'c':
    case 'h':
      return 'c';
    case 'cpp':
    case 'cc':
    case 'cxx':
    case 'hpp':
    case 'hh':
      return 'cpp';
    case 'cs':
      return 'csharp';
    case 'rb':
      return 'ruby';
    case 'php':
      return 'php';
    case 'swift':
      return 'swift';
    case 'sh':
    case 'bash':
    case 'zsh':
      return 'shell';
    case 'json':
    case 'jsonc':
      return 'json';
    case 'yaml':
    case 'yml':
      return 'yaml';
    case 'toml':
      return 'toml';
    case 'ini':
    case 'cfg':
    case 'conf':
    case 'properties':
      return 'ini';
    case 'sql':
      return 'sql';
    case 'xml':
    case 'html':
    case 'htm':
    case 'svg':
      return 'xml';
    case 'css':
    case 'scss':
    case 'less':
      return 'css';
    case 'md':
    case 'markdown':
      return 'markdown';
    case 'lua':
      return 'lua';
    default:
      break;
  }
  switch (base) {
    case 'dockerfile':
    case 'containerfile':
      return 'shell';
    case 'makefile':
    case 'gnumakefile':
      return 'makefile';
    default:
      return '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 语言规格
// ─────────────────────────────────────────────────────────────────────────────

class _LangSpec {
  const _LangSpec({
    this.keywords = const <String>{},
    this.types = const <String>{},
    this.lineComments = const <String>['//'],
    this.blockCommentStart,
    this.blockCommentEnd,
    this.quotes = const <String>['"', "'"],
    this.caseInsensitive = false,
  });

  final Set<String> keywords;
  final Set<String> types;
  final List<String> lineComments;
  final String? blockCommentStart;
  final String? blockCommentEnd;
  final List<String> quotes;

  /// 关键词是否不区分大小写（SQL）。
  final bool caseInsensitive;
}

const Set<String> _cLikeKeywords = <String>{
  'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
  'class', 'const', 'continue', 'default', 'do', 'else', 'enum', 'export',
  'extends', 'final', 'finally', 'for', 'from', 'function', 'get', 'if',
  'implements', 'import', 'in', 'interface', 'is', 'let', 'new', 'of',
  'operator', 'package', 'private', 'protected', 'public', 'return', 'set',
  'static', 'super', 'switch', 'this', 'throw', 'try', 'typedef', 'var',
  'void', 'while', 'with', 'yield',
};

const Set<String> _cLikeTypes = <String>{
  'bool', 'byte', 'char', 'double', 'dynamic', 'false', 'float', 'int',
  'long', 'null', 'num', 'object', 'short', 'string', 'true', 'unsigned',
  'String', 'Object', 'List', 'Map', 'Set', 'Future', 'Stream', 'Iterable',
  'duration', 'Duration', 'DateTime',
};

_LangSpec _specFor(String language) {
  switch (language) {
    case 'dart':
      return const _LangSpec(
        keywords: <String>{..._cLikeKeywords, 'late', 'required', 'covariant', 'sync', 'base', 'sealed', 'when'},
        types: _cLikeTypes,
      );
    case 'javascript':
    case 'jsx':
    case 'typescript':
    case 'tsx':
      return const _LangSpec(
        keywords: <String>{..._cLikeKeywords, 'typeof', 'instanceof', 'delete', 'debugger', 'undefined', 'type', 'declare', 'readonly', 'namespace', 'keyof', 'infer', 'satisfies'},
        types: <String>{'true', 'false', 'null', 'undefined', 'NaN', 'Infinity', 'number', 'boolean', 'any', 'unknown', 'never'},
      );
    case 'python':
      return const _LangSpec(
        keywords: <String>{'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del', 'elif', 'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield', 'match', 'case'},
        types: <String>{'True', 'False', 'None', 'self', 'cls', 'int', 'float', 'str', 'bool', 'list', 'dict', 'set', 'tuple'},
        lineComments: <String>['#'],
      );
    case 'ruby':
      return const _LangSpec(
        keywords: <String>{'BEGIN', 'END', 'alias', 'and', 'begin', 'break', 'case', 'class', 'def', 'defined?', 'do', 'else', 'elsif', 'end', 'ensure', 'for', 'if', 'in', 'module', 'next', 'not', 'or', 'redo', 'rescue', 'retry', 'return', 'self', 'super', 'then', 'undef', 'unless', 'until', 'when', 'while', 'yield', 'require', 'include', 'attr_accessor'},
        types: <String>{'true', 'false', 'nil'},
        lineComments: <String>['#'],
      );
    case 'shell':
    case 'makefile':
      return const _LangSpec(
        keywords: <String>{'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'case', 'esac', 'function', 'in', 'return', 'exit', 'export', 'local', 'readonly', 'source', 'echo', 'cd', 'set', 'unset'},
        types: <String>{'true', 'false'},
        lineComments: <String>['#'],
      );
    case 'yaml':
      return const _LangSpec(
        keywords: <String>{'true', 'false', 'null', 'yes', 'no', 'on', 'off'},
        lineComments: <String>['#'],
      );
    case 'toml':
    case 'ini':
      return const _LangSpec(
        keywords: <String>{'true', 'false'},
        lineComments: <String>['#', ';'],
      );
    case 'json':
      return const _LangSpec(
        keywords: <String>{'true', 'false', 'null'},
        lineComments: <String>[],
        quotes: <String>['"'],
      );
    case 'go':
      return const _LangSpec(
        keywords: <String>{'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', 'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'package', 'range', 'return', 'select', 'struct', 'switch', 'type', 'var'},
        types: <String>{'bool', 'byte', 'complex64', 'complex128', 'error', 'float32', 'float64', 'int', 'int8', 'int16', 'int32', 'int64', 'rune', 'string', 'uint', 'uint8', 'uint16', 'uint32', 'uint64', 'uintptr', 'true', 'false', 'nil', 'iota'},
      );
    case 'rust':
      return const _LangSpec(
        keywords: <String>{'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn', 'else', 'enum', 'extern', 'fn', 'for', 'if', 'impl', 'in', 'let', 'loop', 'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return', 'self', 'Self', 'static', 'struct', 'super', 'trait', 'type', 'unsafe', 'use', 'where', 'while'},
        types: <String>{'bool', 'char', 'f32', 'f64', 'i8', 'i16', 'i32', 'i64', 'i128', 'isize', 'str', 'u8', 'u16', 'u32', 'u64', 'u128', 'usize', 'true', 'false', 'Some', 'None', 'Ok', 'Err'},
      );
    case 'c':
    case 'cpp':
      return const _LangSpec(
        keywords: <String>{'auto', 'break', 'case', 'catch', 'class', 'const', 'constexpr', 'continue', 'default', 'delete', 'do', 'else', 'enum', 'explicit', 'extern', 'for', 'friend', 'goto', 'if', 'inline', 'namespace', 'new', 'operator', 'private', 'protected', 'public', 'register', 'return', 'sizeof', 'static', 'struct', 'switch', 'template', 'this', 'throw', 'try', 'typedef', 'typename', 'union', 'using', 'virtual', 'volatile', 'while'},
        types: <String>{'bool', 'char', 'double', 'float', 'int', 'long', 'short', 'signed', 'unsigned', 'void', 'size_t', 'true', 'false', 'nullptr'},
      );
    case 'csharp':
      return const _LangSpec(
        keywords: <String>{..._cLikeKeywords, 'namespace', 'using', 'internal', 'readonly', 'sealed', 'virtual', 'override', 'params', 'ref', 'out', 'typeof', 'sizeof', 'lock', 'checked', 'unchecked', 'base'},
        types: <String>{'bool', 'byte', 'char', 'decimal', 'double', 'float', 'int', 'long', 'object', 'sbyte', 'short', 'string', 'uint', 'ulong', 'ushort', 'void', 'var', 'true', 'false', 'null'},
      );
    case 'java':
    case 'kotlin':
      return const _LangSpec(
        keywords: <String>{..._cLikeKeywords, 'fun', 'val', 'suspend', 'object', 'companion', 'data', 'sealed', 'internal', 'open', 'override', 'lateinit', 'init', 'constructor', 'when', 'nullable'},
        types: <String>{..._cLikeTypes, 'Boolean', 'Byte', 'Char', 'Double', 'Float', 'Int', 'Long', 'Short', 'Unit', 'Any', 'nothing'},
      );
    case 'swift':
      return const _LangSpec(
        keywords: <String>{'actor', 'as', 'associatedtype', 'async', 'await', 'break', 'case', 'catch', 'class', 'continue', 'default', 'defer', 'deinit', 'do', 'else', 'enum', 'extension', 'fallthrough', 'for', 'func', 'guard', 'if', 'import', 'in', 'init', 'inout', 'internal', 'is', 'let', 'mutating', 'open', 'operator', 'private', 'protocol', 'public', 'repeat', 'return', 'self', 'static', 'struct', 'subscript', 'super', 'switch', 'throw', 'throws', 'try', 'typealias', 'var', 'where', 'while'},
        types: <String>{'Bool', 'Character', 'Double', 'Float', 'Int', 'String', 'Void', 'true', 'false', 'nil', 'Any'},
      );
    case 'php':
      return const _LangSpec(
        keywords: <String>{'abstract', 'and', 'array', 'as', 'break', 'callable', 'case', 'catch', 'class', 'clone', 'const', 'continue', 'declare', 'default', 'do', 'echo', 'else', 'elseif', 'empty', 'endfor', 'endforeach', 'endif', 'endswitch', 'endwhile', 'enum', 'extends', 'final', 'finally', 'fn', 'for', 'foreach', 'function', 'global', 'goto', 'if', 'implements', 'include', 'instanceof', 'interface', 'isset', 'list', 'match', 'namespace', 'new', 'or', 'print', 'private', 'protected', 'public', 'readonly', 'require', 'return', 'static', 'switch', 'throw', 'trait', 'try', 'unset', 'use', 'var', 'while', 'xor', 'yield'},
        types: <String>{'true', 'false', 'null', 'int', 'float', 'string', 'bool', 'array', 'object', 'void', 'mixed'},
      );
    case 'sql':
      return const _LangSpec(
        keywords: <String>{'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create', 'table', 'alter', 'drop', 'index', 'view', 'join', 'left', 'right', 'inner', 'outer', 'on', 'group', 'by', 'order', 'having', 'limit', 'offset', 'union', 'all', 'distinct', 'as', 'and', 'or', 'not', 'null', 'is', 'in', 'between', 'like', 'exists', 'case', 'when', 'then', 'else', 'end', 'primary', 'key', 'foreign', 'references', 'default', 'unique', 'check', 'constraint', 'database', 'if', 'begin', 'commit', 'rollback'},
        lineComments: <String>['--'],
        blockCommentStart: '/*',
        blockCommentEnd: '*/',
        quotes: <String>["'", '"', '`'],
        caseInsensitive: true,
      );
    case 'lua':
      return const _LangSpec(
        keywords: <String>{'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'},
        lineComments: <String>['--'],
        blockCommentStart: '--[[',
        blockCommentEnd: ']]',
      );
    case 'xml':
      return const _LangSpec(
        lineComments: <String>[],
        blockCommentStart: '<!--',
        blockCommentEnd: '-->',
      );
    case 'css':
      return const _LangSpec(
        keywords: <String>{'important', 'media', 'import', 'keyframes', 'supports', 'charset', 'font-face', 'from', 'to'},
        lineComments: <String>[],
        blockCommentStart: '/*',
        blockCommentEnd: '*/',
      );
    case 'markdown':
      return const _LangSpec(
        lineComments: <String>[],
        quotes: <String>['`'],
      );
    default:
      return const _LangSpec();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 扫描器
// ─────────────────────────────────────────────────────────────────────────────

bool _isIdentifierStart(int code) =>
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A) ||
    code == 0x5F ||
    code == 0x24;

bool _isIdentifierPart(int code) =>
    _isIdentifierStart(code) || (code >= 0x30 && code <= 0x39);

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

/// 把源码切成 token 序列（**首尾相接等于原文**）。
List<OgLCodeToken> ogLHighlightCode(String source, String language) {
  final _LangSpec spec = _specFor(language);
  final List<OgLCodeToken> tokens = <OgLCodeToken>[];
  final StringBuffer plain = StringBuffer();

  void flushPlain() {
    if (plain.isNotEmpty) {
      tokens.add(OgLCodeToken(OgLCodeTokenKind.plain, plain.toString()));
      plain.clear();
    }
  }

  void add(OgLCodeTokenKind kind, String text) {
    if (text.isEmpty) {
      return;
    }
    flushPlain();
    tokens.add(OgLCodeToken(kind, text));
  }

  final int n = source.length;
  int i = 0;
  while (i < n) {
    final int code = source.codeUnitAt(i);

    // ── 块注释 ──
    final String? blockStart = spec.blockCommentStart;
    final String? blockEnd = spec.blockCommentEnd;
    if (blockStart != null &&
        blockEnd != null &&
        source.startsWith(blockStart, i)) {
      final int end = source.indexOf(blockEnd, i + blockStart.length);
      final int stop = end < 0 ? n : end + blockEnd.length;
      add(OgLCodeTokenKind.comment, source.substring(i, stop));
      i = stop;
      continue;
    }

    // ── 行注释 ──
    bool matchedLine = false;
    for (final String marker in spec.lineComments) {
      if (marker.isNotEmpty && source.startsWith(marker, i)) {
        final int nl = source.indexOf('\n', i);
        final int stop = nl < 0 ? n : nl;
        add(OgLCodeTokenKind.comment, source.substring(i, stop));
        i = stop;
        matchedLine = true;
        break;
      }
    }
    if (matchedLine) {
      continue;
    }

    // ── 字符串 ──
    final String char = source[i];
    if (spec.quotes.contains(char)) {
      final bool triple = i + 2 < n && source[i + 1] == char && source[i + 2] == char;
      final int quoteLen = triple ? 3 : 1;
      int j = i + quoteLen;
      bool closed = false;
      while (j < n) {
        final int cj = source.codeUnitAt(j);
        if (cj == 0x5C /* \ */) {
          j += 2;
          continue;
        }
        if (triple) {
          if (j + 2 < n &&
              source[j] == char &&
              source[j + 1] == char &&
              source[j + 2] == char) {
            j += 3;
            closed = true;
            break;
          }
        } else {
          if (cj == char.codeUnitAt(0)) {
            j += 1;
            closed = true;
            break;
          }
          if (cj == 0x0A) {
            break; // 普通字符串不跨行。
          }
        }
        j += 1;
      }
      final int stop = closed ? j : (j < n ? j : n);
      add(OgLCodeTokenKind.string, source.substring(i, stop));
      i = stop;
      continue;
    }

    // ── 数字 ──
    // 只吞"数字 / 下划线 / 小数点"；十六进制字母仅在 0x/0X 前缀之后才吞，
    // 否则会把 `1abc` 这类标识符误并进数字（颜色高亮错位）。
    if (_isDigit(code)) {
      bool hex = false;
      int j = i;
      if (code == 0x30 /* 0 */ &&
          i + 1 < n &&
          (source.codeUnitAt(i + 1) | 0x20) == 0x78 /* x */) {
        hex = true;
        j = i + 2;
      }
      while (j < n) {
        final int cj = source.codeUnitAt(j);
        if (_isDigit(cj) || cj == 0x5F /* _ */ || cj == 0x2E /* . */) {
          j += 1;
          continue;
        }
        if (hex && (cj | 0x20) >= 0x61 && (cj | 0x20) <= 0x66) {
          j += 1;
          continue;
        }
        break;
      }
      add(OgLCodeTokenKind.number, source.substring(i, j));
      i = j;
      continue;
    }

    // ── 标识符 / 关键词 ──
    if (_isIdentifierStart(code)) {
      int j = i;
      while (j < n && _isIdentifierPart(source.codeUnitAt(j))) {
        j += 1;
      }
      final String word = source.substring(i, j);
      final String probe = spec.caseInsensitive ? word.toLowerCase() : word;
      if (spec.keywords.contains(probe)) {
        add(OgLCodeTokenKind.keyword, word);
      } else if (spec.types.contains(probe)) {
        add(OgLCodeTokenKind.type, word);
      } else {
        plain.write(word);
      }
      i = j;
      continue;
    }

    plain.writeCharCode(code);
    i += 1;
  }
  flushPlain();
  return tokens;
}

// ─────────────────────────────────────────────────────────────────────────────
// 渲染组件
// ─────────────────────────────────────────────────────────────────────────────

/// 代码视图：高亮 +（可选）行号 +（可选）自动换行 + 可调字号。
class CodeView extends StatelessWidget {
  /// 创建代码视图。
  const CodeView({
    required this.code,
    this.language = '',
    this.fontSize = 13,
    this.wrap = false,
    this.highlight = true,
    this.showLineNumbers = true,
    super.key,
  });

  /// 源码。
  final String code;

  /// 语言标识（空则不高亮关键词，仍识别注释 / 字符串）。
  final String language;

  /// 字号。
  final double fontSize;

  /// 是否自动换行（否则横向滚动）。
  final bool wrap;

  /// 是否启用高亮。
  final bool highlight;

  /// 是否显示行号（仅在 `wrap == false` 时对齐可靠）。
  final bool showLineNumbers;

  TextStyle _styleFor(OgLCodeTokenKind kind, ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    switch (kind) {
      case OgLCodeTokenKind.keyword:
        return TextStyle(color: scheme.primary, fontWeight: FontWeight.w600);
      case OgLCodeTokenKind.type:
        return TextStyle(color: scheme.tertiary);
      case OgLCodeTokenKind.string:
        return TextStyle(color: scheme.tertiary);
      case OgLCodeTokenKind.comment:
        return TextStyle(
          color: scheme.outline,
          fontStyle: FontStyle.italic,
        );
      case OgLCodeTokenKind.number:
        return TextStyle(color: scheme.secondary);
      case OgLCodeTokenKind.plain:
        return const TextStyle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle base = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.5,
    );
    // 极端输入护栏：过大退回纯文本，避免生成海量 span / 组件。
    final bool tooLarge = code.length > kOgLCodeHighlightMaxChars;
    final bool doHighlight = highlight && !tooLarge;
    final List<OgLCodeToken> tokens = doHighlight
        ? ogLHighlightCode(code, language)
        : <OgLCodeToken>[OgLCodeToken(OgLCodeTokenKind.plain, code)];
    final TextSpan span = TextSpan(
      style: base,
      children: <TextSpan>[
        for (final OgLCodeToken token in tokens)
          TextSpan(text: token.text, style: _styleFor(token.kind, theme)),
      ],
    );

    final Widget text = SelectableText.rich(span);

    if (wrap) {
      return text;
    }

    final Widget scrollable = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: text,
    );

    // 行号仅在"不换行 + 行数可控"时渲染；两个条件缺一都会破坏对齐或造成
    // 海量组件，故直接退回无行号渲染（内容本身不受影响）。
    final int lines = '\n'.allMatches(code).length + 1;
    if (!showLineNumbers || lines > kOgLCodeGutterMaxLines) {
      return scrollable;
    }

    final int digits = '$lines'.length;
    final Widget gutter = Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int line = 1; line <= lines; line++)
            Text(
              '$line',
              style: base.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: digits * fontSize * 0.62 + 12, child: gutter),
        Expanded(child: scrollable),
      ],
    );
  }
}