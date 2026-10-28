#!/bin/bash
# QuotaBar 构建 + 安装：编译原生菜单栏 App → 装到 ~/Applications → 配置/采集器就位 → 开机自启 → 启动
set -euo pipefail
cd "$(dirname "$0")"

APP="QuotaBar.app"
APP_BIN="$HOME/Applications/$APP/Contents/MacOS/QuotaBar"
SUPPORT="$HOME/Library/Application Support/QuotaBar"
AGENT="$HOME/Library/LaunchAgents/com.tianzhao.quotabar.plist"

echo "① 生成图标"
python3 assets/make_icons.py

echo "② 编译"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/Info.plist"
cp assets/whale-bar.png assets/whale-color.png "$APP/Contents/Resources/"
swiftc -O -swift-version 5 app/main.swift -o "$APP/Contents/MacOS/QuotaBar"

echo "③ 签名（ad-hoc）"
codesign --force --sign - "$APP"

echo "④ 安装到 ~/Applications"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/$APP"
cp -R "$APP" "$HOME/Applications/"

echo "⑤ 配置与采集器就位"
mkdir -p "$SUPPORT"
cp collector/collect.mjs "$SUPPORT/collect.mjs"
if [ ! -f "$SUPPORT/config.json" ]; then
  cp config/config.json "$SUPPORT/config.json"
  echo "   已生成默认配置：$SUPPORT/config.json（填入各 API key / 手工额度后点刷新）"
fi

echo "⑥ 首次采集"
NODE="/opt/homebrew/bin/node"; [ -x "$NODE" ] || NODE="/usr/local/bin/node"; [ -x "$NODE" ] || NODE="$(which node)"
"$NODE" "$SUPPORT/collect.mjs" || true

echo "⑦ 登录自启（LaunchAgent）"
mkdir -p "$HOME/Library/LaunchAgents"
sed "s#@@APPBIN@@#$APP_BIN#" com.tianzhao.quotabar.plist > "$AGENT"
launchctl bootout "gui/$(id -u)/com.tianzhao.quotabar" 2>/dev/null || true
sleep 0.8
launchctl bootstrap "gui/$(id -u)" "$AGENT"

echo "⑧ 重启单实例"
launchctl kickstart -k "gui/$(id -u)/com.tianzhao.quotabar"

echo "✅ 完成。菜单栏应有小鲸鱼图标；点击查看各模型额度进度条。"
echo "   配置文件：$SUPPORT/config.json"
