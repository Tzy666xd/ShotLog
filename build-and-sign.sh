#!/bin/bash
# ShotLog 构建脚本：编译 + Apple Development 证书签名。
#
# 为什么不用 ad-hoc：ad-hoc 的签名身份绑定二进制哈希，每次重编译 macOS 会当成
# 新 app，相册授权跟着丢失。用开发证书签名后身份绑定证书，重编译不影响已授
# 予的权限——只需授权一次。
#
# 用法：./build-and-sign.sh [--check]
#   --check  只编译到 /tmp 不覆盖桌面 App，用于语法自检

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/ShotLog/ShotLog.swift"
APP="$HOME/Desktop/ShotLog.app"
BIN="$APP/Contents/MacOS/ShotLog"
IDENTITY="Apple Development: 8618966919552 (BX7C7A677C)"
TOOLCHAIN="/Applications/Xcode.app/Contents/Developer"
# -load-plugin-library：sandbox_exec 嵌套拒绝，swift-plugin-server 起不来，
# 不显式加载 libSwiftUIMacros 就会报 "StateMacro could not be found"。
PLUGIN="$TOOLCHAIN/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"

if [ "${1:-}" = "--check" ]; then
    echo "==> [check] 编译到 /tmp/ShotLog-check（不改动桌面 App）"
    DEVELOPER_DIR="$TOOLCHAIN" xcrun swiftc -O -parse-as-library \
        -load-plugin-library "$PLUGIN" "$SRC" -o /tmp/ShotLog-check
    echo "==> [check] 通过：$(wc -l < "$SRC" | tr -d ' ') 行，$(stat -f%z /tmp/ShotLog-check) 字节"
    exit 0
fi

echo "==> 编译 $SRC"
DEVELOPER_DIR="$TOOLCHAIN" xcrun swiftc -O -parse-as-library \
    -load-plugin-library "$PLUGIN" "$SRC" -o "$BIN"

echo "==> 签名（${IDENTITY}）"
# 先清掉旧的 _CodeSignature，否则 codesign 会去校验上一次的 sealed resource 表，
# 报 "a sealed resource is missing or invalid"。
# 上次签名中断残留的 Contents/MacOS/ShotLog.cstemp 也要一并删掉。
rm -rf "$APP/Contents/_CodeSignature"
rm -f "$BIN.cstemp"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | head -2

echo "==> 完成"
echo "    行数: $(wc -l < "$SRC" | tr -d ' ')"
echo "    字节: $(stat -f%z "$BIN")"
echo "    sha:  $(shasum -a 256 "$BIN" | cut -c1-16)…"
echo "    签名: $(codesign -dv --verbose=2 "$APP" 2>&1 | grep -m1 'Authority' | sed 's/Authority=//')"
