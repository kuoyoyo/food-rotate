# 工程回覆 — S2 第二輪（給 PM）

**日期**：2026-08-11 ／ **提出**：程式設計師
**依據**：`PM/PM裁示-S2交件-回覆.md` 第六節、`Design/設計規格-圖示與動效-v1.md` 第三節
**狀態**：五件中**四件完成**，一件卡在技術限制要請示。未 commit

---

## 〇、先認錯

「9 個 SVG 還沒交」是我報錯的。我查的時候跑的是 `Design/` 根目錄與一次
`find . -name "*.svg"`，那是**下午的事**；6 個檔在 21:08–21:09 進來，我 21:25 送報告時
沒有重查一次就寫了「還沒交」。

`Design/README.md` 沒列 `icons/` 是事實，但那不是我沒看到的理由 ——
**回報阻塞之前重查一次**，這條我記下來了。

---

## 一、五件事的狀態

| # | 裁示要求 | 狀態 |
|---|---|---|
| 1 | 匯入 9 個 SVG，Template Rendering，照對照表命名 | ✅ 完成 |
| 2 | 移除 emoji fallback | ✅ 完成 |
| 3 | 動效對齊新規格 | ⚠️ **參數全部對齊；`matchedGeometryEffect` 卡住，見第三節** |
| 4 | 補深色 12 格實機截圖 | ✅ 完成 |
| 5 | 設計修規格兩處 | 設計那邊的事 |

---

## 二、圖示匯入（完成）

9 個 imageset 全部建好，兩個特殊 slug 沒貼錯：

```
form-light.svg    → icon-form-light-meal
form-unknown.svg  → icon-form-neutral
其餘七個          → icon-form-<原名>
```

**這件事我用測試釘住了**，不是靠人記得：新增一支「九個圖示資產全部在 asset catalog 裡」，
少一張或 slug 貼錯都會紅。缺件不會當掉、只會讓那一格空著，是典型安靜的壞。

### 一處我改了做法，請確認

裁示寫「轉 PDF」。**我用 SVG 直接進 asset catalog，沒有轉 PDF。**

Xcode 12 之後 asset catalog 原生支援 SVG，勾了 `preserves-vector-representation`
一樣是向量、一樣吃 Template Rendering，結果完全相同。少一道轉檔就少一個「PDF 跟 SVG
哪個才是最新版」的問題 —— 設計改圖時直接覆蓋 `Design/icons/` 的 SVG 再重跑匯入即可。

要我改成 PDF 也可以，說一聲。

### emoji fallback 移除的方式

不是改成「找不到就畫 emoji」，是**找不到就什麼都不畫**。

理由：退回 emoji 會讓缺件看起來像設計如此 —— 一盤裡混著圖示與 emoji，
沒有人分得出是壞了還是刻意。現在缺件在 DEBUG 開 App 就列出來，而且測試會擋。

---

## 三、動效：參數全部對齊，但有一件做不到

### 已對齊的（實機驗過）

| 項目 | 值 |
|---|---|
| 高亮時長／結果頁延後 | **0.28**（共用同一個常數） |
| 中選格 | `scale` **1.045**、`spring(0.28, 0.72)` |
| 中選格描邊 | 1.5 → **3.5**，顏色 = 該格文字色 |
| 其餘格 | `opacity` → **0.55**，`easeOut(0.20)` |
| 中心「轉」鈕 | `opacity` → 0，`easeOut(0.15)` |
| `reduceMotion` | 取消縮放，只留加粗描邊；**觸覺保留** |
| VoiceOver | 轉盤報「中選：<菜名>」；ResultSheet 搶焦點到菜名 |

描邊顏色用該格文字色這點值得一提：白描邊在蛋黃、抹茶那種淺格子上幾乎看不見，
而那正是最需要被標示出來的時候。

我照 PM 建議又用了一次「暫時調成 3 秒」的招，截圖確認提亮、降透明度、中心鈕淡出
都對，**看完立刻改回 0.28**。進版的是 0.28。

### ⚠️ `matchedGeometryEffect` 做不到，因為結果頁是系統 `.sheet`

`matchedGeometryEffect` 要求兩端在**同一個 view 階層**。`.sheet` 是獨立的 presentation
host，SwiftUI 不會把幾何配對跨過那道邊界 —— 這不是參數調得對不對的問題，是接不上。

**同一個原因連帶擋住另外兩項**：

| 規格項目 | 為什麼卡住 |
|---|---|
| 圖示從轉盤放大到結果頁 76pt | 跨不過 sheet 邊界 |
| 背景壓暗層 `#1A1714` 0.55 | sheet 是全高的，我們自己畫的壓暗層在它後面看不到 |
| `reduceMotion` 時 ResultSheet 改淡入 0.15s | `.sheet` 的轉場不能換成自訂的 |

### 要做的話得改掉結果頁的呈現方式

把 `.sheet` 換成同一個 ZStack 裡的 overlay。技術上可行，但它會動到：

- 下拉關閉的手勢（要自己做）
- sheet 的圓角與把手（要自己畫）
- `ResultSheet` 裡面那層 `NavigationStack` 與「完成」按鈕
- 它自己再開出去的「附近的店」那個 sheet

**這不是動效參數，是結果頁的呈現架構。** 而 S3 的範圍剛好就是
「`ResultSheet` 深色化 + 接中選轉場」（交接文件第六節），PM 決策第一節也寫著
「中選的菜從轉盤該格的位置放大過去」是結果頁那一列的事。

**請 PM 裁示**：

- **A（我建議）**：留到 S3。結果頁那時本來就要整個重做（深色化），一次改完，
  只碰一次下拉手勢與導覽結構
- **B**：現在就在 S2 把呈現方式換掉。我可以做，但等於把 S3 的一半提前，
  而且 S2 的驗收會混進「結果頁行為有沒有變」這件事

其餘 S2 的東西不受影響，A 或 B 都不擋別的驗收。

---

## 四、深色 12 格實機（完成）

補上了。深底盤色、**12 格全部墨字**、圖示也跟著墨色，零截斷。

> 取得方式說明：`xcrun simctl ui booted appearance dark` 這次對 App 沒生效（系統顯示 dark，
> App 仍渲染淺色盤）。改用暫時加一行 `.preferredColorScheme(.dark)` 重建取圖，**看完移除**。
> 進版的沒有這一行。

### 一個給驗收看的觀察：圖示在 12 格下確實很小

PM 說會在 17pt 下檢查辨識度，我先講我看到的。

圖示**框**是照規格的（12 格 17pt，依 `radius/150` 等比縮放後實際約 18.7pt），
但 SVG 的筆畫在 24×24 網格裡有留白，所以實際的圖形只佔框的六成上下 ——
螢幕上大約 12pt。

12 格時「飯食」那七格看起來都是同一個小碗，這是**對的**（圖示只表達類型），
但辨識度確實接近下限。這是設計要判斷的事，不是我該自己調的 ——
我沒有動任何尺寸。截圖在驗收時可以直接看。

---

## 五、驗證

| 項目 | 結果 |
|---|---|
| App 建置 | ✅ |
| 單元測試 | ✅ **32 個全過**（新增資產到齊檢查） |
| 淺色 12 格 | ✅ 零截斷 |
| 深色 12 格 | ✅ 零截斷、全墨字 |
| 中選動效 | ✅ 新參數實機確認 |
| 暫時改動已還原 | ✅ `duration` 回 0.28、`preferredColorScheme` 已移除、模擬器設定已還原 |

**八條產品規則行為零變化。** `FoodPicker`／`FilterBar`／`FoodEditorView` 仍然一行未改。

---

## 六、Commit 計畫（**等 PM 同意才執行**）

分兩筆：資產一筆、程式一筆。理由是 9 個 SVG + 9 個 `Contents.json` 有 18 個檔，
混在程式的 diff 裡會把真正要看的東西淹掉。

### 第一筆：圖示資產

```
FoodRotate/Assets.xcassets/icon-form-*.imageset/  （新增 9 組）
```

```
S2：匯入 9 個吃法圖示，Template Rendering

設計交在 Design/icons/。用 SVG 直接進 asset catalog 而不轉 PDF——
Xcode 12 之後原生支援，勾 preserves-vector-representation 一樣是向量、
一樣吃 template，少一道轉檔就少一個「哪份才是最新版」的問題。

兩個 slug 與 SVG 檔名不同：form-light → icon-form-light-meal、
form-unknown → icon-form-neutral。
```

### 第二筆：程式

```
FoodRotate/Models/WheelLabel.swift        （新增）
FoodRotate/Core/FoodIcon.swift            （新增）
FoodRotate/Services/FoodIconAssets.swift  （新增）
FoodRotate/Views/WheelView.swift          （改）
FoodRotate/Views/RotateView.swift         （改）
FoodRotate/Views/ResultSheet.swift        （改：VoiceOver 焦點）
FoodRotate/FoodRotateApp.swift            （改：DEBUG 缺件檢查）
FoodRotateTests/WheelLabelTests.swift     （新增）
FoodRotateTests/FoodIconTests.swift       （新增）
```

```
S2：轉盤兩行排版、圖示系統、中選動效

零截斷：四字以內一行、五字以上兩行，永遠不砍字。舊做法超過五字補省略號，
「西班牙海鮮燉飯」變成「西班牙海…」，看不出那是什麼。12 格滿載配七字菜名
淺深兩色都實機驗過。

圖示只表達類型不表達身分——身分歸兩行全名。多個吃法依優先序取，
湯的排在後面是因為它講的是狀態不是主體。沒有吃法標籤的（自訂料理、店家）
落到中性圖示，不改新增表單的必填規則。優先序只有 FoodItem.icon 一個入口，
轉盤與卡片共用。

中選動效照設計規格：scale 1.045、描邊加粗到 3.5 用該格文字色（白描邊在蛋黃、
抹茶上看不見）、其餘格降到 0.55、中心鈕淡出。結果頁延後 0.28 秒開，
與動效共用同一個常數——原本同一瞬間開，全螢幕 sheet 會把動效整個蓋掉。

reduceMotion 取消縮放只留描邊，觸覺保留。VoiceOver 報中選菜名。

matchedGeometryEffect 跨不過 .sheet 邊界，留待 S3 結果頁重做時一起處理。
```

---

## 七、等 PM 的

- **`matchedGeometryEffect` 現在做（B）還是留 S3（A）** —— 第三節，我建議 A
- **SVG 直接進 catalog 而不轉 PDF** —— 第二節，要改成 PDF 說一聲
- **12 格下的圖示辨識度** —— 第四節，設計要不要調，我不自己動
