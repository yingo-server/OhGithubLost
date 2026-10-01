#!/usr/bin/env python3
"""校验 APK 的签名证书是否等于指定 keystore 里的证书（CI 护栏）。

为什么需要它：Flutter 模板的 release 用 Gradle 的 "debug" 签名配置，
而 runner 上 AGP **未必**采用我们铺到 `~/.android/debug.keystore` 的那把
（实证：两次构建的证书互不相同 → 覆盖安装报"签名不一致"）。
因此构建后先**显式重签**，再用本脚本**逐包校验**，不一致直接让流水线失败。

用法：
    python3 tool/verify_apk_cert.py --apk <apk> --keystore <jks>
        [--storepass android] [--alias androiddebugkey]

退出码：0 = 证书一致；1 = 不一致或解析失败。
"""
import argparse
import hashlib
import re
import subprocess
import sys

MAGIC = b'APK Sig Block 42'


def pretty(digest_hex):
    """把十六进制摘要写成 `AA:BB:...` 形式。"""
    return ':'.join(digest_hex[i:i + 2] for i in range(0, len(digest_hex), 2))


def expected_cert(keystore, storepass, alias):
    """从 keystore 导出证书 DER。"""
    proc = subprocess.run(
        ['keytool', '-exportcert', '-rfc', '-keystore', keystore,
         '-storepass', storepass, '-alias', alias],
        capture_output=True, text=True)
    if proc.returncode != 0:
        print('无法读取 keystore：%s' % proc.stderr.strip())
        return None
    body = re.search(
        r'-----BEGIN CERTIFICATE-----(.+?)-----END CERTIFICATE-----',
        proc.stdout, re.S)
    if not body:
        return None
    import base64
    return base64.b64decode(''.join(body.group(1).split()))


def certs_in_signing_block(apk_path):
    """只在实际签名块窗口里找证书（避免捡到应用内嵌的 CA）。"""
    data = open(apk_path, 'rb').read()
    magic = data.rfind(MAGIC)
    if magic < 0:
        return []
    window = data[max(0, magic - 20000):magic]
    out = []
    i = 0
    while True:
        i = window.find(b'\x30\x82', i)
        if i < 0:
            return out
        length = (window[i + 2] << 8) | window[i + 3]
        der = window[i:i + 4 + length]
        if len(der) == 4 + length and 400 < length < 3000:
            out.append(der)
        i += 4


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', required=True)
    parser.add_argument('--keystore', required=True)
    parser.add_argument('--storepass', default='android')
    parser.add_argument('--alias', default='androiddebugkey')
    args = parser.parse_args()

    expected = expected_cert(args.keystore, args.storepass, args.alias)
    if expected is None:
        sys.exit('无法从 keystore 导出证书')
    exp_fp = pretty(hashlib.sha256(expected).hexdigest()).upper()
    print('期望证书 SHA-256: %s' % exp_fp)

    found = certs_in_signing_block(args.apk)
    if not found:
        print('!! %s 没解析到签名证书' % args.apk)
        sys.exit(1)
    for der in found:
        got = pretty(hashlib.sha256(der).hexdigest()).upper()
        if der == expected:
            print('签名证书 SHA-256: %s  ✅ 与期望一致' % got)
            return
        print('签名证书 SHA-256: %s  ✗ 与期望不一致' % got)
    sys.exit(1)


if __name__ == '__main__':
    main()