#!/usr/bin/env bash
# 把 DTPUnlock.dylib 注入已解密的 .app 并重签
#
# 前置:
#   1. APP 目录必须来自「已解密」的包（bagbak / dumpdecrypted 导出）
#      —— 直接拿 App Store 的加密 ipa 注入，安装后必闪退
#   2. 已安装 insert_dylib (https://github.com/Tyilo/insert_dylib)
#      或改用 Sideloadly 的 "dylib injection" 功能（更省事）
#   3. 准备一个可用的签名身份，例如:
#      EXPORT TEAM_ID=你的TeamID  EXPORT SIGN_ID="Apple Development: xxx (XXXXXXXXXX)"
#
# 用法: ./inject.sh /path/to/Payload/DTPAIiPad.app
set -euo pipefail

APP="${1:?用法: ./inject.sh <Payload/DTPAIiPad.app>}"
DYLIB="$(cd "$(dirname "$0")" && pwd)/DTPUnlock.dylib"
SIGN_ID="${SIGN_ID:-}"
EXEC="$APP/DTPAIiPad"

[ -f "$DYLIB" ] || { echo "缺少 DTPUnlock.dylib，先跑 ./build.sh"; exit 1; }
[ -f "$EXEC" ]  || { echo "找不到可执行文件: $EXEC"; exit 1; }

# 1. 拷贝 dylib 到 Frameworks 目录
mkdir -p "$APP/Frameworks"
cp "$DYLIB" "$APP/Frameworks/DTPUnlock.dylib"

# 2. 给主二进制加一条 LC_LOAD_DYLIB
#    优先用 insert_dylib；没有的话自动退回 LIEF（pip install lief 即可）
if command -v insert_dylib >/dev/null 2>&1; then
    insert_dylib --inplace --strip-codesig --all-yes \
        "@executable_path/Frameworks/DTPUnlock.dylib" "$EXEC"
else
    echo "未找到 insert_dylib，改用 LIEF"
    python3 - "$EXEC" <<'PY'
import sys, lief
path = sys.argv[1]
binary = lief.MachO.parse(path).at(0)
binary.add_library("@executable_path/Frameworks/DTPUnlock.dylib")
config = lief.MachO.Builder.config_t()
config.force_emit_all = True
lief.MachO.Binary.write(binary, path, config)
print("LC_LOAD_DYLIB added via LIEF")
PY
fi

# 3. 重新签名（顺序很重要：先 Frameworks 里的 dylib，再整个 .app）
if [ -n "$SIGN_ID" ]; then
    codesign -f -s "$SIGN_ID" "$APP/Frameworks/DTPUnlock.dylib"
    codesign -f -s "$SIGN_ID" "$EXEC"
    codesign -f -s "$SIGN_ID" "$APP"
else
    echo "未提供 SIGN_ID，使用 ad-hoc 签名（仅供已越狱设备/调试，正常安装会校验失败）"
    ldid -S "$APP/Frameworks/DTPUnlock.dylib" || true
    ldid -S "$EXEC" || true
fi

echo "完成。接下来:"
echo "  - 打包: cd Payload 上层目录 && zip -qr DulaTrackPro-unlocked.ipa Payload"
echo "  - 安装: Sideloadly / AltStore / Xcode Devices 窗口"
echo "  - 日志: 连接 Console.app 过滤 [DTPUnlock]，确认是否打到 checkEntitlement"
