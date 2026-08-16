# 工程回覆 — S5-B 其餘四頁（給 PM）

**日期**：2026-08-13 ／ **提出**：程式設計師
**依據**：`Coder/PM派工-S5-工程.md` 第二節、`Design/設計規格-其餘四頁-v1.md`、`Design/PM核可-設計規格其餘四頁-v1.md`
**狀態**：做完。**未 commit** ——但有一件 commit 事故要先講，見第十節。

---

## 〇、先講兩件你會想先知道的

1. **`6757733` 那筆「文件：PM 文件收進 PM/，新增專案 README」把我當時做一半的 S5-B 程式碼一起 commit 進去了，而且已經推上 GitHub。** 不是我下的指令。細節與處理選項在第十節。
2. **有兩處我做了超出規格字面的判斷**，都是套色、不改行為，但你可能會想退回：新增料理表單、附近的店的導覽列。第八節。

---

## 一、四頁 + 附近的店

| 檔案 | 做了什麼 |
|---|---|
| `Views/DishListRow.swift`（新增） | 歷史與我的清單共用的列。emoji 28pt + 菜名 + 一行說明 + `TagBadge` + 右側附加物，列高 56 |
| `Views/HistoryView.swift` | 列換成 `DishListRow`、空狀態套色、頁底與卡片走 token |
| `Views/FoodEditorView.swift` | `MyListView` 的兩區列換成 `DishListRow`、新增按鈕實心主色、還原走 `sauce`、還原成預設走 `negative` |
| `Views/SettingsView.swift` | `Form` 結構不動只換色與字級；`CopyrightFooter` token 化；新增 `SegmentedAppearance` |
| `Views/RootView.swift` | `WelcomeView` 的 hero 換成六格轉盤標記、四條說明縮成一行、按鈕實心主色；`init` 套一次分段控制 appearance |
| `Views/NearbyRestaurantsView.swift` | 只套色不改版面，維持淺色 |
| `Tools/make-icon.swift` | 加第三個輸出：首次啟動頁的轉盤標記 |
| `Assets.xcassets/mark-wheel.imageset` | 上面那支腳本產出的 PNG |

`FoodPicker.swift` 從 S1 到現在仍然**零變更**。

---

## 二、三件你先講的事

### 1. emoji 保留，用 `TagBadge` 補類型 ✅

歷史與我的清單都保留使用者的 emoji，兩頁都加了角標。

**實機剛好抓到一個印證這個決定的畫面**：我塞了一道測試用的「公司樓下自助餐」，它**沒有任何標籤**（模擬使用者只填名字就存），所以角標一個都不顯示 —— 但 🍱 還在（見 `L-mylist.png` 第二列）。如果照「一律換線稿」做，這一列就會只剩一個中性刀叉，**一整列變成沒有任何辨識資訊**。設計那句「不是換一種視覺，是降級成無資訊」在實機上就是這一格。

角標沒有標籤時**不顯示**而不是寫「未分類」，跟 `TagBadge` 原本的行為一致。

### 2. 🎡 → 六格轉盤標記，由 `make-icon.swift` 產出 ✅

照你的建議走腳本，理由同 S5-A：色值烙進 SVG 就會跟色盤分岔。

**幾何與配色完全沿用彩色版 icon**（`colorful.slices`、同一段 `draw`），只多一個差別：

> `Palette.background` 改成可為 `nil`。`nil` 的時候分隔線與指針缺口不是「拿背景色蓋」，而是用 `.clear` 混合模式**挖穿**。

這樣同一張 PNG 在淺色與深色頁面上都是**頁底色從縫裡透出來**，不需要兩張圖。淺深兩張截圖並排看得很清楚（`L-welcome.png` 的縫是米白，`D-welcome.png` 的縫是深墨）。

**這支腳本的改寫沒有動到既有的兩張輸出** —— 我重跑一次，彩色版與去色版跟 catalog 裡的檔案 **`cmp` 逐位元組相同**。這是我對「重構不該改變產物」的自證方式。

### 3. 分段控制：不填主色、未選文字用 `text` ✅（但有一項實測發現，見第三節）

顏色走 `UISegmentedControl.appearance()`，**套在 `RootView.init`，不是 `SettingsView`** ——
appearance 只影響**之後才建立**的控制項，套在設定頁的話轉盤頁那個「吃什麼／去哪吃」會維持系統色，
**同一個 App 裡兩個同型別的控制項長不一樣**。

> ⚠️ 這表示**轉盤頁的來源切換器也一起換色了**。那一頁 S1–S4 已經驗收過，所以我明講：
> 這是一個你已經驗收過的畫面上的視覺變動。`D-rotate.png` / `L-rotate.png` 可以看。
> 我認為要一起換（兩個控制項不該不一樣），但這是你的決定。

---

## 三、⚠️ 實測發現：控制底的顏色套不進去，但結論不變

我用取色驗每一個顏色，發現**一項與規格不符**：

| 元素 | 規格值 | 實測值 | 判定 |
|---|---|---|---|
| 選中段底（淺／深） | `card` `#F8F5EE`／`#23201B` | **`#F8F5EE`／`#23201B`** | ✅ 完全相同 |
| 選中與未選文字（淺／深） | `text` `#241E18`／`#EFE9DE` | **`#241E18`／`#EFE9DE`** | ✅ 完全相同 |
| **控制底（淺／深）** | `hairline` `#DAD7D0`／`#3B3832` | **`#CDCBC6`／`#494745`** | ❌ **不是 token** |

原因：`selectedSegmentTintColor` 是直接畫的，而 `backgroundColor` 被 UIKit 自己的一層材質蓋過去，
**最後看到的是它疊完的結果**，不是我給的值。

### 那條對比結論反而更站得住

我用實測值重算未選文字的對比：

| 配對 | 規格（假設 `hairline`） | 實測底色 |
|---|---|---|
| 淺 未選文字 `text` | 11.47 | **10.17** ✅ |
| 深 未選文字 `text` | 9.67 | **7.65** ✅ |
| 淺 `textSecondary`（設計否掉的那個） | 3.90 ❌ | **3.45** ❌ 更差 |

**兩個都還在 4.5 以上，而被否掉的那個在真實底色上更不合格。** 設計那個判斷是對的，
而且比他自己算的更對。

### 我沒有硬把它改成 token

要精確控制得改用 `setBackgroundImage`，那會**連圓角一起接手** ——
1×1 的實色圖拉開之後控制項就變成直角矩形，為了 3% 的色差換掉系統的圓角，不划算。
**這是我判斷後決定不做的，不是漏掉。**

---

## 四、我獨立重算的對比（不看規格，自己算一遍）

| 配對 | 值 | 用在哪 |
|---|---|---|
| 淺 `onSauce` on `sauce` | **6.31** ✅ | 新增料理、開始用 |
| 深 `onSauce` on `sauce` | **5.10** ✅ | 同上（**深墨，不是白**） |
| 深 **白字** on `sauce` | **3.50** ❌ | 這就是那條不准改回去的紅線的數字 |
| 淺／深 `sauce` on `card` | 6.31／4.64 ✅ | 「還原」 |
| 淺／深 `negative` on `card` | 5.59／8.46 ✅ | 「還原成預設」 |
| 淺／深 `TagBadge` 文字 on `hairline` | 11.47／9.67 ✅ | 兩頁的角標 |
| 淺／深 `textSecondary` on `pageBackground` | 4.67／7.28 ✅ | 分組 footer、首次啟動說明 |
| 淺／深 `textSecondary` on `card` | **5.14／6.62** ✅ | 歷史的條件摘要、我的清單的分類 |

### 一個小更正

規格第二節把「條件摘要」的對比寫成 **4.67／7.28** —— 那組數字是 `textSecondary` 疊在
**`pageBackground`** 上的值。實際上那一行長在**卡片**上，正確的值是 **5.14／6.62**。
兩個都過 4.5，所以**沒有任何東西要改**，只是數字歸屬要對。

---

## 五、為了不改行為，兩頁維持 `List`（一項與規格不符）

規格第二節寫「容器：`card` 底、`radiusLarge` 10、**1px `hairline` 邊框**」。

**我做到了前兩項，沒有做 1px 邊框。**

理由：歷史的刪除紀錄與我的清單的移除自訂料理都是 `.onDelete` 的左滑，
**那只在 `List` 上有效**（這正是 S4 左滑第一版踩過的坑）。換成自製容器就能畫邊框，
但會失去那個左滑 —— **那是行為，S5 的紅線是「套 token 不等於改行為」。**

所以底色與分隔線走 `List` 自己的接口（`listRowBackground`、`listRowSeparatorTint`、
`alignmentGuide(.listRowSeparatorLeading)`），容器圓角由 `insetGrouped` 提供。

**分隔線的縮排我量了**：卡片左緣在 48px（16pt），分隔線起點在 216px，
差 **56.0pt** = `space12` + emoji 32 + `space12`，剛好對齊 emoji 右緣。

---

## 六、一項我沒做：「清除全部紀錄」的 `negative`

規格第二節要求它用 `negative` 不用系統紅。**我沒有做，也沒有留一段假裝有做的程式碼。**

那個動作在 `Menu` 裡。選單項目的外觀由系統畫，`role: .destructive` 的紅換不掉 ——
`foregroundStyle` 不會生效，`tint` 只會改到外面那顆 `⋯` 的顏色（而那顆不是破壞性動作，
染紅反而是錯的）。要套色就得把這個動作移出選單，**那是改頁面結構，不是套色。**

而且**我沒有辦法實機驗證選單裡的顏色**（開選單需要點按），所以就算我寫了也只能標「未實測」。
兩個理由加起來，我選擇不做並寫在這裡。**要不要移出選單請你裁示。**

---

## 七、✅ 驗證（每一頁淺深各一次，改 appearance 都先 shutdown 再 boot）

| 頁面 | 淺色 | 深色 |
|---|---|---|
| 首次啟動說明 | ✅ `L-welcome.png` | ✅ `D-welcome.png` |
| 歷史（有紀錄） | ✅ `L-history.png` | ✅ `D-history.png` |
| 歷史（空狀態） | ✅ 全新安裝時看的 | ✅ |
| 設定 | ✅ `L-settings.png` | ✅ `D-settings.png` |
| 我的清單 | ✅ `L-mylist.png` | ✅ `D-mylist.png` |
| 新增料理 | ✅ `L-editor.png` | ✅ `D-editor.png` |
| 附近的店 | ✅ `L-nearby.png` | ✅ **深色系統下仍然是淺色** `D-nearby.png` |
| 轉盤 | ✅ `L-rotate.png` | ✅ `D-rotate.png` |
| 結果頁 | ✅ **淺色系統下的固定深色** `L-result.png` | ✅ |

截圖在 `/private/tmp/claude-501/-Users-kuoyoyo/407195b7-eb58-4135-a656-4f5576cf3375/scratchpad/`。

### 不是只用眼睛看，關鍵顏色是取色量出來的

| 量測 | 結果 |
|---|---|
| 歷史頁 頁底／卡片（深） | `#1A1714`／`#23201B` = `Dark.pageBackground`／`Dark.card` |
| 歷史頁 分隔線（深） | `#3B3832` = `Dark.hairline`，起點 56.0pt |
| 我的清單「還原」（深） | `#D9674F` = `Dark.sauce` |
| 我的清單「還原成預設」（深） | `#EFAE6E` = `Dark.negative` |
| 分段控制（淺／深） | 見第三節 |
| 轉盤頁 頁底（深） | `#000000` ← **不是 token，見第九節** |

### 取證用的暫時程式碼全部移除

模擬器沒辦法用指令碼點按，所以我暫時加了三個啟動參數（進我的清單、開新增料理、開附近的店）。
**全部拿掉了**，並且用同一組參數再跑一次確認**已經沒有作用**（`D-final-clean.png` 停在設定頁）。
`grep 暫時` 在 `FoodRotate/` 底下只剩 `NearbySearch.swift` 兩句本來就有的錯誤訊息文案。

### 行為沒有變

| 項目 | 確認 |
|---|---|
| 43 個單元測試 | ✅ 全過 |
| 自訂料理參加抽樣 | ✅ 塞進去的「阿婆麵線」出現在轉盤上 |
| 排除名單生效 | ✅ 排除掉的牛肉麵、滷肉飯**沒有**出現在轉盤上 |
| 設定頁的開關、歷史的還原、清單的刪除 | ✅ 一律沒動，只有顏色與字級 |

> 截圖裡的「阿婆麵線」「公司樓下自助餐」與兩筆排除是我塞進模擬器的測試資料
> （寫在模擬器的 UserDefaults，不在專案裡）。你要乾淨環境的話重裝 App 就沒了。

---

## 八、兩個超出規格字面的判斷，請你裁示

### 1. 新增料理的表單也套了色

規格第三節寫「表單本身（`TagGrid`）S4 已完成，不動」。我照字面只做列表頁時，
拿去跟其他頁並排看 —— **這一頁的分組卡片是系統的藍灰，其他每一頁都是暖色 token**，
在深色下差異特別明顯。

所以我做了**跟設定頁完全相同的一件事**：換頁底、卡片、分組標題與 footer 的顏色。
**欄位、`TagGrid`、`canSave`、儲存邏輯一個字沒動。**

我認為這是規格漏講而不是規格禁止（「不動」指的是 `TagGrid` 元件），但這是我的判斷，
**你要退回我就拆掉。**

### 2. 附近的店釘成淺色，連導覽列一起

規格第六節寫「維持淺色、不做深色版」。我照這個把頁面內容釘成淺色之後，
**在深色系統下發現導覽列的標題還是白色，疊在淺色頁面上，實測對比 1.1，幾乎看不見** ——
以前沒事是因為舊的 `systemGroupedBackground` 在深色下也是深的。

**這個問題是我自己造成的**，所以我補了 `.preferredColorScheme(.light)` 把整個 sheet 釘住。
`D-nearby.png` 現在跟淺色版一模一樣。

「固定淺色」這個決定本來就必須連導覽列一起釘，我認為這是實作該補的，不是新的設計決定。

---

## 九、轉盤頁的頁底（你裁示「改一行吧」，已改）

`RotateView.swift:363` 原本是 `Color(.systemGroupedBackground)` —— S1–S4 換掉的是那一頁的
**內容**，頁底一直是系統色。深色下它是純黑，其他每一頁都是 `#1A1714`。

改成 `Theme.pageBackground(for: colorScheme)`，一行。

| 模式 | 改前 | 改後（取色量測） |
|---|---|---|
| 深色 | `#000000` | **`#1A1714`** = `Dark.pageBackground` ✅ |
| 淺色 | 系統分組色 | **`#EFEAE0`** = `Light.pageBackground` ✅ |

**順帶一個沒預期到的好處**：轉盤的分隔線畫的就是 `pageBackground`（S5-A 改的），
以前頁底跟它不同色，那六條縫其實是「一條深墨線畫在黑底上」；現在**縫與頁底同一個值**，
轉盤真的變成「地色從縫裡透出來」。這是 S5-A 那個決定原本就想要的效果，
到現在才真正成立。

43 個測試仍然全過。

---

## 十、⚠️ Commit 事故（不是我做的，但要講清楚）

我做 S5-B 的期間，工作區被另一個 session commit 了：

```
6757733 文件：PM 文件收進 PM/，新增專案 README     ← 這一筆
16544c2 Update README.md table formatting
0924e69 Revert "Update README.md table formatting"
```

`6757733` 的訊息是文件搬移與新增 README，但它實際包含了**我當時做一半的 S5-B 程式碼**：

```
FoodRotate/Views/DishListRow.swift          （新檔，119 行）
FoodRotate/Views/FoodEditorView.swift
FoodRotate/Views/HistoryView.swift
FoodRotate/Views/SettingsView.swift（部分）
Tools/make-icon.swift
FoodRotate/Assets.xcassets/mark-wheel.imageset/
```

那個時間點的程式碼是**中間狀態**：新增料理按鈕還是會糊成深色圓塊的 `plus.circle.fill`、
我的清單還有一條多餘的分隔線、表單還沒套色。**也就是說 GitHub 上現在有一筆
訊息寫著「文件」、內容包含未經你驗收的半成品程式碼的 commit。**

我確認了 `main` 與 `origin/main` 同步 —— **它已經推上去了。**

### 兩個選項，你決定

| | 做法 | 代價 |
|---|---|---|
| **A（我建議）** | 不動歷史，我把剩下的差異當成一筆「S5-B」commit 疊上去，commit 訊息裡註明前半段誤入 `6757733` | 歷史上有一筆訊息與內容不符的 commit，但最終的樹是對的 |
| B | `git reset --soft 4c8b669` 重新切成乾淨的兩筆 | **要 force-push 一個已經推上去的分支**，如果有別人拉過就會出事 |

我傾向 A：訊息錯了可以用文件補救，改寫已推送的歷史風險大得多。**但這是你的決定，
我在你回覆之前不會做任何 git 操作。**

---

## 十一、Commit 計畫（等你驗過）

```
FoodRotate/Views/DishListRow.swift            （其實已在 6757733，這裡是後續修正）
FoodRotate/Views/HistoryView.swift            （同上）
FoodRotate/Views/FoodEditorView.swift         （改：我的清單套 token + 表單套色）
FoodRotate/Views/SettingsView.swift           （改：套 token + SegmentedAppearance + CopyrightFooter）
FoodRotate/Views/RootView.swift               （改：WelcomeView + appearance 套用點）
FoodRotate/Views/NearbyRestaurantsView.swift  （改：只套色 + 釘淺色）
FoodRotate/Views/ResultSheet.swift            （改：CopyrightFooter 傳 .dark，一行）
FoodRotate/Views/RotateView.swift             （改：頁底改 token，一行；你裁示的）
Tools/make-icon.swift                         （同上，已在 6757733）
```

`ResultSheet.swift` 那一行是連帶的：`CopyrightFooter` token 化之後，
固定深色的結果頁必須明講 `.dark`，否則淺色模式下版權那三行會用淺色的文字色疊在深卡片上
（`L-result.png` 是修好之後的樣子）。**結果頁其他部分一個字沒動。**
