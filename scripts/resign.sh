#!/usr/bin/env bash
# 用你自己的证书（.p12）和描述文件（.mobileprovision）给未签名的 IPA 签名。只能在 macOS 上运行。
#
# 用法：
#   scripts/resign.sh <未签名.ipa> <证书.p12> <p12密码> <App描述文件> [小组件描述文件] [输出.ipa]
#
# - App 描述文件可以是精确 ID（如 com.you.pupu）也可以是通配符（TEAMID.*）。
# - 小组件描述文件：精确 ID 的 App 描述文件需要再给小组件单独一个（ID 为 <App ID>.widget）；
#   不提供且 App 描述文件不是通配符时，会去掉小组件后签名。
# - 描述文件里如果带有 App Group，会自动把 App 里的 AppGroupID 改成它，小组件就能和 App 共享数据。
set -euo pipefail

IPA="$1"; P12="$2"; P12_PASS="$3"; APP_PROFILE="$4"
WIDGET_PROFILE="${5:-}"
OUT="${6:-Pupudiary-signed.ipa}"

WORK="$(mktemp -d)"
trap 'security delete-keychain "$WORK/sign.keychain-db" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

PB=/usr/libexec/PlistBuddy

# 1. 导入证书到临时钥匙串
KEYCHAIN="$WORK/sign.keychain-db"
KC_PASS="$(uuidgen)"
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | sed 's/"//g')
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk 'NR==1 {print $2}')"
[ -n "$IDENTITY" ] || { echo "❌ 证书里没有找到可用的签名身份"; exit 1; }
echo "✅ 使用证书：$(security find-identity -v -p codesigning "$KEYCHAIN" | head -1)"

# 2. 解包
unzip -q "$IPA" -d "$WORK/ipa"
APP="$(find "$WORK/ipa/Payload" -maxdepth 1 -name '*.app' | head -1)"
APPEX="$APP/PlugIns/PupudiaryWidget.appex"
ORIG_ID="$($PB -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"

# 解析描述文件：输出 entitlements 文件，返回最终 bundle id
prepare_profile() { # $1=profile $2=默认 bundle id $3=输出前缀
  local profile="$1" fallback="$2" prefix="$3"
  security cms -D -i "$profile" > "$prefix.plist"
  $PB -x -c 'Print :Entitlements' "$prefix.plist" > "$prefix.ent.plist"
  local appid team bid
  appid="$($PB -c 'Print :Entitlements:application-identifier' "$prefix.plist")"
  team="$($PB -c 'Print :TeamIdentifier:0' "$prefix.plist")"
  bid="${appid#"$team".}"
  if [[ "$bid" == *"*"* ]]; then
    bid="$fallback"
    $PB -c "Set :application-identifier $team.$bid" "$prefix.ent.plist"
  fi
  echo "$bid"
}

APP_ID="$(prepare_profile "$APP_PROFILE" "$ORIG_ID" "$WORK/app")"
APP_WILDCARD=false
if $PB -c 'Print :Entitlements:application-identifier' "$WORK/app.plist" | grep -q '\*'; then APP_WILDCARD=true; fi
echo "📦 App Bundle ID：$APP_ID"

GROUP="$($PB -c 'Print :Entitlements:com.apple.security.application-groups:0' "$WORK/app.plist" 2>/dev/null || true)"
if [ -n "$GROUP" ]; then
  echo "👥 App Group：$GROUP"
else
  echo "⚠️  描述文件不含 App Group，小组件将无法读取 App 数据（仍可一键记录，但数据会分开保存）"
  $PB -c 'Delete :com.apple.security.application-groups' "$WORK/app.ent.plist" 2>/dev/null || true
fi

set_info() { # $1=Info.plist $2=bundle id
  $PB -c "Set :CFBundleIdentifier $2" "$1"
  if [ -n "$GROUP" ]; then $PB -c "Set :AppGroupID $GROUP" "$1" 2>/dev/null || $PB -c "Add :AppGroupID string $GROUP" "$1"; fi
}

# 3. 小组件
if [ -d "$APPEX" ]; then
  WIDGET_DEFAULT_ID="$APP_ID.widget"
  if [ -n "$WIDGET_PROFILE" ]; then
    W_ID="$(prepare_profile "$WIDGET_PROFILE" "$WIDGET_DEFAULT_ID" "$WORK/widget")"
    cp "$WIDGET_PROFILE" "$APPEX/embedded.mobileprovision"
  elif $APP_WILDCARD; then
    W_ID="$WIDGET_DEFAULT_ID"
    cp "$WORK/app.ent.plist" "$WORK/widget.ent.plist"
    $PB -c "Set :application-identifier $($PB -c 'Print :TeamIdentifier:0' "$WORK/app.plist").$W_ID" "$WORK/widget.ent.plist"
    cp "$APP_PROFILE" "$APPEX/embedded.mobileprovision"
  else
    echo "⚠️  没有小组件描述文件，移除小组件后签名"
    rm -rf "$APPEX"
  fi
  if [ -d "$APPEX" ]; then
    [ -n "$GROUP" ] || $PB -c 'Delete :com.apple.security.application-groups' "$WORK/widget.ent.plist" 2>/dev/null || true
    set_info "$APPEX/Info.plist" "$W_ID"
    codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" --entitlements "$WORK/widget.ent.plist" "$APPEX"
    echo "🧩 小组件已签名：$W_ID"
  fi
fi

# 4. 主 App
set_info "$APP/Info.plist" "$APP_ID"
cp "$APP_PROFILE" "$APP/embedded.mobileprovision"
codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" --entitlements "$WORK/app.ent.plist" "$APP"
codesign --verify --deep --strict "$APP"

# 5. 打包
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
(cd "$WORK/ipa" && zip -qry "$OUT_ABS" Payload)
echo "🎉 已生成：$OUT_ABS"
