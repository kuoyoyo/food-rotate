#!/bin/bash
# FoodRotate 模擬器驅動。用法見 SKILL.md。
#
# 座標系統：tap / drag 收的是「截圖裡的像素座標」，不是 point。
# 你截了圖、在圖上量到按鈕在 (601, 1919)，就 tap 601 1919。
# 換算成 macOS 螢幕座標是這支腳本的事，而且是量出來的不是寫死的。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SKILL_DIR/../../.." && pwd)"
SCHEME=FoodRotate
BUNDLE_ID=com.kuoyo.foodrotate
DEVICE_NAME="${FOODROTATE_DEVICE:-iPhone 17 Pro}"
SHOT_DIR="${FOODROTATE_SHOTS:-${TMPDIR:-/tmp}/foodrotate-shots}"
CACHE_DIR="${TMPDIR:-/tmp}/foodrotate-driver"
CLICK_BIN="$CACHE_DIR/click"

mkdir -p "$SHOT_DIR" "$CACHE_DIR"

die() { echo "error: $*" >&2; exit 1; }

udid() {
  local u
  u=$(xcrun simctl list devices booted -j 2>/dev/null \
      | python3 -c 'import json,sys
d=json.load(sys.stdin)["devices"]
for rt in d:
    for dev in d[rt]:
        print(dev["udid"]); raise SystemExit' 2>/dev/null || true)
  if [ -z "$u" ]; then
    u=$(xcrun simctl list devices -j \
        | python3 -c "import json,sys
d=json.load(sys.stdin)['devices']
for rt in d:
    for dev in d[rt]:
        if dev['name']=='$DEVICE_NAME' and dev['isAvailable']:
            print(dev['udid']); raise SystemExit")
  fi
  [ -n "$u" ] || die "找不到裝置「$DEVICE_NAME」"
  echo "$u"
}

# click 這支很小，第一次用才編，編到 cache 不進 repo。
ensure_click() {
  if [ ! -x "$CLICK_BIN" ] || [ "$SKILL_DIR/click.swift" -nt "$CLICK_BIN" ]; then
    swiftc -O "$SKILL_DIR/click.swift" -o "$CLICK_BIN" \
      || die "編譯 click.swift 失敗（需要 Xcode command line tools）"
  fi
}

# 模擬器畫面在 macOS 螢幕上的位置與大小。
# 視窗會被移動、縮放（⌘1/⌘2/⌘3），所以每次都重新問，不要快取。
screen_geometry() {
  osascript -e 'tell application "System Events" to tell process "Simulator" to get {value of attribute "AXPosition", value of attribute "AXSize"} of (first UI element of window 1 whose role is "AXGroup")' 2>/dev/null \
    | tr -d ' ' | tr ',' ' '
}

# 截圖的像素尺寸。裝置換了就不一樣，所以量一次存起來。
shot_dimensions() {
  # 分兩行不是風格問題：macOS 內建的 bash 3.2 在同一個 local 裡
  # 展開後面那個變數時，前面那個還沒指派。
  local u=$1
  local cache="$CACHE_DIR/$u.dims"
  if [ ! -f "$cache" ]; then
    local tmp="$CACHE_DIR/probe.png"
    xcrun simctl io "$u" screenshot "$tmp" >/dev/null 2>&1 \
      || die "截圖失敗，模擬器開著嗎？"
    sips -g pixelWidth -g pixelHeight "$tmp" \
      | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}' > "$cache"
  fi
  cat "$cache"
}

# 截圖像素座標 -> macOS 螢幕座標
map_point() {
  local u=$1 px=$2 py=$3
  local ox oy w h iw ih
  read -r ox oy w h < <(screen_geometry)
  [ -n "${h:-}" ] || die "抓不到模擬器視窗。先跑 driver.sh boot（headless 的模擬器沒有視窗可以點）"
  read -r iw ih < <(shot_dimensions "$u")
  python3 -c "print(round($ox + $px * $w / $iw), round($oy + $py * $h / $ih))"
}

focus() { osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1; sleep 0.3; }

cmd=${1:-}; shift || true
case "$cmd" in

  boot)
    U=$(udid)
    xcrun simctl bootstatus "$U" -b >/dev/null 2>&1 || xcrun simctl boot "$U" 2>/dev/null || true
    # 一定要開 Simulator.app：headless 的模擬器截得到圖但沒有視窗可以點。
    open -a Simulator --args -CurrentDeviceUDID "$U"
    for _ in $(seq 1 30); do
      [ -n "$(screen_geometry)" ] && break
      sleep 1
    done
    [ -n "$(screen_geometry)" ] || die "Simulator.app 起來了但抓不到視窗（檢查「輔助使用」權限）"
    echo "booted $U  ($DEVICE_NAME)"
    ;;

  build)
    cd "$PROJECT_DIR"
    xcodebuild build -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,name=$DEVICE_NAME" "$@"
    ;;

  test)
    cd "$PROJECT_DIR"
    xcodebuild test -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,name=$DEVICE_NAME" "$@"
    ;;

  install)
    U=$(udid); cd "$PROJECT_DIR"
    APP=$(xcodebuild -scheme "$SCHEME" \
            -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
            -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')
    [ -d "$APP" ] || die "找不到 build 產物，先跑 driver.sh build（找的是 $APP）"
    xcrun simctl install "$U" "$APP"
    echo "installed $APP"
    ;;

  launch)   xcrun simctl launch "$(udid)" "$BUNDLE_ID" ;;
  relaunch) U=$(udid); xcrun simctl terminate "$U" "$BUNDLE_ID" >/dev/null 2>&1 || true
            sleep 1; xcrun simctl launch "$U" "$BUNDLE_ID" ;;

  tap)
    [ $# -eq 2 ] || die "用法：driver.sh tap <px_x> <px_y>"
    U=$(udid); ensure_click; focus
    read -r SX SY < <(map_point "$U" "$1" "$2")
    "$CLICK_BIN" "$SX" "$SY"
    echo "tap($1,$2) -> screen($SX,$SY)"
    ;;

  drag)
    [ $# -eq 4 ] || die "用法：driver.sh drag <x1> <y1> <x2> <y2>"
    U=$(udid); ensure_click; focus
    read -r AX AY < <(map_point "$U" "$1" "$2")
    read -r BX BY < <(map_point "$U" "$3" "$4")
    "$CLICK_BIN" "$AX" "$AY" "$BX" "$BY"
    echo "drag($1,$2)->($3,$4)"
    ;;

  shot)
    [ $# -ge 1 ] || die "用法：driver.sh shot <名稱>"
    U=$(udid); OUT="$SHOT_DIR/$1.png"
    xcrun simctl io "$U" screenshot "$OUT" >/dev/null 2>&1 || die "截圖失敗"
    echo "$OUT"
    ;;

  appearance)
    [ "${1:-}" = light ] || [ "${1:-}" = dark ] || die "用法：driver.sh appearance light|dark"
    xcrun simctl ui "$(udid)" appearance "$1"; echo "appearance $1"
    ;;

  location)
    # 授權 + 設座標 + 重啟。App 在跑的時候設座標不會生效，
    # 它會用開啟時拿到的那一筆（預設是舊金山）。
    [ $# -eq 2 ] || die "用法：driver.sh location <lat> <lon>"
    U=$(udid)
    xcrun simctl privacy "$U" grant location-always "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl terminate "$U" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl location "$U" clear >/dev/null 2>&1 || true
    xcrun simctl location "$U" set "$1,$2"
    sleep 1
    xcrun simctl launch "$U" "$BUNDLE_ID" >/dev/null
    echo "location $1,$2（已重啟 App 讓它重新定位）"
    ;;

  geometry) echo "screen: $(screen_geometry) | shot: $(shot_dimensions "$(udid)")" ;;

  *)
    cat <<'USAGE'
driver.sh <命令>

  boot                    開機並開啟 Simulator.app（點擊的前提）
  build | test            xcodebuild
  install                 裝上剛 build 好的 .app
  launch | relaunch       啟動 / 重啟 App
  tap <x> <y>             點擊（座標＝截圖裡的像素）
  drag <x1> <y1> <x2> <y2>  拖曳／捲動
  shot <名稱>              截圖，印出路徑
  appearance light|dark   淺深色
  location <lat> <lon>    授權定位 + 設座標 + 重啟
  geometry                印出目前的座標對應（除錯用）
USAGE
    exit 1
    ;;
esac
