/// L2 中枢级 · 下载器安全边界测试（文件名净化 + 协议白名单）。
///
/// 这两条是**下载器必须自己守住**的边界，不能外包给第三方库：
/// 1. **文件名净化** —— `fileName` 的来源之一是 Release 附件名，仓库所有者
///    完全可控；不做净化等于把路径构造交给 `background_downloader` 的内部
///    实现，而那不在本仓库内、无法审计；
/// 2. **协议白名单** —— 加速通道地址由**用户填写**，允许 `file://` 等协议
///    等于让远端内容指定去读本机任意文件，且非 http 协议在浏览器端无法走 CORS。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/ix/ix_download.dart';

void main() {
  group('文件名净化', () {
    test('路径穿越被截断到末段', () {
      expect(ogLSafeDownloadFileName('../../etc/passwd'), 'passwd');
      expect(ogLSafeDownloadFileName(r'..\..\windows\system32\cmd.exe'),
          'cmd.exe');
      expect(ogLSafeDownloadFileName('/absolute/path/file.zip'), 'file.zip');
    });

    test('空与纯点号回落到默认名', () {
      expect(ogLSafeDownloadFileName(''), 'download');
      expect(ogLSafeDownloadFileName('   '), 'download');
      expect(ogLSafeDownloadFileName('..'), 'download');
      expect(ogLSafeDownloadFileName('.'), 'download');
      expect(ogLSafeDownloadFileName('...'), 'download');
      expect(ogLSafeDownloadFileName('..', fallback: 'x'), 'x');
    });

    test('控制字符与非法字符被剔除', () {
      expect(ogLSafeDownloadFileName('a\u0000b.txt'), 'ab.txt');
      expect(ogLSafeDownloadFileName('bad\nname.txt'), 'badname.txt');
      expect(ogLSafeDownloadFileName('file<>:"?*.txt'), 'file.txt');
    });

    test('空白收敛、前导点与尾随点被去掉', () {
      expect(ogLSafeDownloadFileName('  spaced name.zip  '), 'spaced name.zip');
      expect(ogLSafeDownloadFileName('.gitignore'), 'gitignore');
      expect(ogLSafeDownloadFileName('report.'), 'report');
    });

    test('Windows 保留设备名被改名', () {
      expect(ogLSafeDownloadFileName('con.txt'), '_con.txt');
      expect(ogLSafeDownloadFileName('NUL'), '_NUL');
      expect(ogLSafeDownloadFileName('com1.log'), '_com1.log');
    });

    test('扩展名被保住，过长扩展名整个丢弃', () {
      expect(ogLSafeDownloadFileName('archive.tar.gz'), 'archive.tar.gz');
      expect(
        ogLSafeDownloadFileName('OGL-v6.0.0-Android.arm64-v8a.zip'),
        'OGL-v6.0.0-Android.arm64-v8a.zip',
      );
      expect(ogLSafeDownloadFileName('name.${'e' * 30}'), 'name');
    });

    test('超长名限长 120 且保住扩展名', () {
      expect(ogLSafeDownloadFileName('${'x' * 200}.zip'), '${'x' * 120}.zip');
      expect(ogLSafeDownloadFileName('a' * 200), 'a' * 120);
      expect(ogLSafeDownloadFileName('.${'x' * 200}.zip'),
          '${'x' * 120}.zip');
    });

    test('非 ASCII 文件名原样保留', () {
      expect(ogLSafeDownloadFileName('中文文件名.txt'), '中文文件名.txt');
    });
  });

  group('协议白名单', () {
    test('http / https 通过', () {
      expect(ogLAssertDownloadUrl('https://github.com/a/b'), isNotEmpty);
      expect(ogLAssertDownloadUrl('http://github.com/a/b'), isNotEmpty);
      expect(
        ogLAssertDownloadUrl('https://proxy.344977.xyz/https://github.com/a'),
        isNotEmpty,
      );
    });

    test('非 http(s) 一律拒绝', () {
      expect(() => ogLAssertDownloadUrl('file:///etc/passwd'),
          throwsArgumentError);
      expect(() => ogLAssertDownloadUrl('data:text/plain,hi'),
          throwsArgumentError);
      expect(() => ogLAssertDownloadUrl('javascript:alert(1)'),
          throwsArgumentError);
      expect(() => ogLAssertDownloadUrl(''), throwsArgumentError);
      expect(() => ogLAssertDownloadUrl('not a url'), throwsArgumentError);
    });
  });
}