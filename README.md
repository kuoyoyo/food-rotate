# 食物轉盤 Food Rotate

不知道吃什麼的時候，讓它幫你決定。

iOS App，SwiftUI 寫的。**完全離線**，50 道料理內建在 App 裡，不需要網路、不上傳任何資料。

---

## 兩個模式

| | 做什麼 |
| **吃什麼** | 從 50 道內建料理裡抽，可以用 34 個標籤篩條件。完全離線 |
| **去哪吃** | 找附近實際有在營業的餐廳。只有這個模式會用到定位與網路 |

轉完會給一張結果頁：菜名、為什麼可以吃、要注意的地方，還可以直接去找附近有賣的店。

---

## 幾個刻意的決定

**忌口永遠不會被自動放寬。** 選了「無牛」，湊不滿轉盤格數時 App 會放寬別的條件，
但不會偷偷把牛肉麵放回來。放寬了哪個維度也一定寫在畫面上。

**「去哪吃」的菜系是搜尋關鍵字，不是篩選條件。** 地圖 API 沒有菜系欄位，
我們做的是拿字比對店名。找不到時會明說「附近沒有 X 的店，改列一般餐廳」，不假裝篩到了。

**每道菜都有缺點。** 候選清單會告訴你其他選項好在哪、雷在哪 —— 目的是讓你有依據推翻它，
不是說服你接受。

---

## 技術

| | |
|---|---|
| 平台 | iOS 26.0+ |
| 語言 | Swift 6.0（嚴格併發） |
| UI | SwiftUI，轉盤是 `Canvas` 手繪 + 自訂緩動狀態機 |
| 儲存 | SwiftData（只存轉盤紀錄）、UserDefaults（自訂料理與設定） |
| 地圖 | MapKit |
| 外部套件 | **零** |

---

## 專案結構

```
FoodRotate/
  Core/        資料模型與抽樣邏輯，只 import Foundation
  Models/      幾何、排版、設定
  Services/    定位、地圖搜尋、觸覺、資產
  Views/       畫面
  DesignTokens.swift   色票與尺寸的唯一來源（不 import SwiftUI）
  Theme.swift          把 token 包成 SwiftUI 型別

FoodRotateTests/       43 個單元測試
FoodRotateWidget/      桌面小工具
Tools/make-icon.swift  App Icon 產生器，讀同一份 DesignTokens
```

`Core/` 只用 Foundation 是刻意的界線 —— 抽樣邏輯不該知道畫面長什麼樣。

### 文件

專案用三個資料夾分角色存放協作文件，各自有 `README`：

| 資料夾 | 內容 |
|---|---|
| `Design/` | 設計規格、視覺提案、圖示原始檔 |
| `Coder/` | 工程交接、實作回報、驗收與問題單 |
| `PM/` | 跨角色的統整與裁示 |

---

## 建置

```bash
xcodebuild build -scheme FoodRotate -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test  -scheme FoodRotate -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

或直接用 Xcode 開 `FoodRotate.xcodeproj`。

---

## 目前進度

視覺與體驗改版分五個階段，S1–S5A 已完成，S5B（其餘四頁套用 design token）進行中。

各階段的規格、驗收與判斷理由都留在 `Design/`、`Coder/`、`PM/` 裡。

---

**製作**：Claude Code ／ **設計**：kuoyo
© 2026 kuoyo
