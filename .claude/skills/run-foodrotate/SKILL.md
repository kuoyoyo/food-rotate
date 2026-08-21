---
name: run-foodrotate
description: Build, run, and drive FoodRotate (食物轉盤) in the iOS Simulator. Use when asked to start the app, run its tests, build it, take a screenshot of a screen, or interact with the running app — tap, scroll, switch light/dark, or set a simulated location.
---

FoodRotate 是 iOS SwiftUI App。驅動它的東西是
`.claude/skills/run-foodrotate/driver.sh` —— 它包住 `xcodebuild` 與
`xcrun simctl`，並且補上 simctl 沒有的那一塊：**點擊**。

所有路徑相對於 repo 根目錄。

## Prerequisites

Xcode + command line tools（`swiftc` 要能跑，driver 會用它編一支點擊工具）。
另外要有 **iPhone 17 Pro 模擬器**（專案要求 iOS 26.0+）。換裝置設
`FOODROTATE_DEVICE`。

**「輔助使用」權限**：driver 靠 CGEvent 送滑鼠事件，跑它的那個程式
（終端機／Claude Code）必須在「系統設定 → 隱私權與安全性 → 輔助使用」裡被勾選。
沒勾的話 tap 會安靜地沒反應。

## 開場：一定要先 boot

```bash
.claude/skills/run-foodrotate/driver.sh boot
```

**這一步不能跳過，即使 `simctl list devices` 已經顯示 booted。**
模擬器可以在沒有 Simulator.app 視窗的情況下開機 —— 那個狀態截得到圖，
但沒有視窗可以送滑鼠事件，所有 tap 都會落空。`boot` 會把 Simulator.app 開起來
並等到視窗真的出現。

## Build / Test

```bash
.claude/skills/run-foodrotate/driver.sh build
.claude/skills/run-foodrotate/driver.sh test
.claude/skills/run-foodrotate/driver.sh install
.claude/skills/run-foodrotate/driver.sh launch      # 或 relaunch
```

`test` 目前是 **99 tests in 21 suites**（Swift Testing，不是 XCTest，
所以輸出是 `✔ Test run with N tests ... passed`，沒有 `Executed N tests`）。

## Run（agent 路徑）

```bash
D=.claude/skills/run-foodrotate/driver.sh

$D relaunch                    # 先確認 App 真的在前景
sleep 3
$D shot before                 # 印出 PNG 路徑，讀它
$D tap 601 1919                # 點「開始轉」
sleep 9                        # 轉盤動畫約 8 秒
$D shot after
```

**別跳過 `relaunch`。** `test` 跑完、`install` 裝完之後模擬器會停在主畫面，
這時候 tap 會點在桌面圖示上，截圖是一張漂亮的 iOS 主畫面。
**每次截圖都要真的看過** —— 點錯地方不會有任何錯誤訊息。

**座標就是截圖裡的像素座標。** 你截了圖、看到按鈕在 (601, 1919)，就 `tap 601 1919`。
不用換算 point —— driver 每次都去問模擬器視窗現在多大、在哪，自己算。
視窗被搬動或用 ⌘1/⌘2/⌘3 改了縮放都不影響。

其他命令：

```bash
$D drag 600 2000 600 1100      # 捲動（由下往上拖 = 往下捲）
$D appearance dark             # 淺深色
$D location 25.0339 121.5645   # 授權定位 + 設座標 + 重啟 App
$D geometry                    # 印出目前座標對應，tap 失準時看這個
```

截圖預設落在 `$TMPDIR/foodrotate-shots/`，用 `FOODROTATE_SHOTS` 改。

### 這個 session 實際點中過的位置

iPhone 17 Pro，截圖 1206×2622：

| 目標 | 座標 |
|---|---|
| 「吃什麼」／「去哪吃」分頁 | `321 419` ／ `878 419` |
| 選條件（展開篩選） | `220 605` |
| 換一組 | `1009 605` |
| 開始轉 | `601 1919` |
| 結果頁「完成」 | `1100 254` |
| 轉盤／歷史／設定 分頁 | `343 2463` ／ `600 2463` ／ `858 2463` |

## Run（人的路徑）

Xcode 開 `FoodRotate.xcodeproj` 按 ⌘R。要看畫面用這個就好，
但它沒有辦法讓 agent 點東西。

## Gotchas

- **`xcrun simctl` 沒有 tap 子命令，而 `osascript` 的 `click at` 在 Simulator 上
  回 -25204。** 這就是 `click.swift`（CGEvent）存在的理由。這台機器上沒有
  `idb` 也沒有 `cliclick`，python 也沒有 `Quartz` 模組。

- **`simctl location set` 對已經在跑的 App 沒有效果。** App 用的是啟動時拿到的
  那一筆定位。一定要 terminate → set → launch，`driver.sh location` 就是這個順序。

- **模擬器的預設位置是舊金山。** 「去哪吃」不設座標會抓到 Tad's Steak House、
  John's Grill 這些 SF 的店。要台灣的結果就先跑 `location`。
  截圖要外流時**用公開地標的座標，不要用真實住處**。

- **轉盤轉完會停在傾斜的角度**，格子上的字有一半是倒的。要拍正面的轉盤，
  按「換一組」（`tap 1009 605`）讓它回正。

- **結果頁是深色卡片**，即使 App 在淺色模式。那是設計，不是抓錯狀態。

- **`screencapture -R` 在這台機器上回 `could not create image from rect`**
  （缺螢幕錄製權限）。所以校準座標不能靠 macOS 截圖，driver 是去問
  Simulator 視窗的 accessibility 樹（`AXGroup` 就是裝置畫面那一塊）。

- **`DEVLOG.md:311` 提到的 `-autoSpin` 啟動參數已經不存在了。** 程式碼裡
  沒有任何 `ProcessInfo` 讀取，別照 DEVLOG 試著用啟動參數跳到某個畫面。

- **macOS 內建的是 bash 3.2**：`local a=$1 b="$a"` 裡的 `$a` 展開時 `a` 還沒指派。
  改 driver 時要記得分行寫。

## Troubleshooting

| 症狀 | 原因與修法 |
|---|---|
| `抓不到模擬器視窗` | Simulator.app 沒開（headless booted）。跑 `driver.sh boot` |
| tap 印出座標但畫面沒反應 | 「輔助使用」沒勾到跑 driver 的那個程式 |
| tap 點到隔壁的東西 | 視窗被搬動或縮放改了。driver 每次都重量，先跑 `geometry` 看數字對不對 |
| `編譯 click.swift 失敗` | `xcode-select --install`，或 `sudo xcode-select -s /Applications/Xcode.app` |
| 「去哪吃」空的或都是英文店名 | 沒設座標（預設舊金山），或沒授權。跑 `driver.sh location <lat> <lon>` |
| `找不到 build 產物` | 先 `driver.sh build`，再 `install` |
