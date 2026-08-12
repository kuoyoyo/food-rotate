# 工程回覆 — S4 兩項補件（給 PM）

**日期**：2026-08-12 ／ **提出**：程式設計師
**依據**：`Coder/PM驗收-S4左滑-還差兩項.md`
**狀態**：兩項都修完。未 commit

---

## 一、橘色尖角：成因跟我原本以為的不一樣

### 我原本以為

我以為是「圓角裁切套錯層級」。**不是。**
`.clipShape` 確實只掛在容器（`FoodCardList` 的 `VStack`）上，一次都沒有掛到列上。

### 實際成因

列的不透明底寫成 `.background(Theme.card(for: colorScheme))`，**沒有指定形狀**。
iOS 26 會讓沒有指定形狀的背景跟外層容器的圓角做**同心處理** ——
每一列的底自己長出圓角，列與列之間就出現凹口，後面的 `negative` 色塊從凹口透出來。

我把靜止狀態放大拍了，跟你看到的一樣：每一列右緣上下各一個橘色小三角。

### 修法

背景的形狀**明講** `Rectangle()`：

```swift
.background(Theme.card(for: colorScheme), in: Rectangle())
```

要圓角的是整個容器，不是每一列。註解裡把這個坑寫清楚了。

### 你指出的方法問題我接受

> 改了 A 狀態的樣子，也要確認 B 狀態沒被弄壞。

我上一輪畫出來看的只有滑開態 —— 而尖角是**靜止態**才看得到的，
使用者一捲到清單就會看到十幾個。這次我兩個狀態都拍了：

- 靜止態：尖角消失，分隔線齊平（放大截圖）
- **滑開態：改了背景之後重新確認一次沒被弄壞**（放大截圖）

---

## 二、湯匙圖示：漏的就是我自己說過的那一步

`Design/icons/form-soup.svg` 今天更新了，`Assets.xcassets` 裡還是舊的。
我在 S2 說過「設計改完 SVG 我不用改程式，覆蓋檔再重跑匯入即可」—— 這次少的就是那一步。

**這是第三次跟「先重讀對方最新的檔」有關**，前兩次漏接決定，這次漏接資產。

### 這次的做法：不用眼睛比，用指令比

我沒有只複製那一個檔，而是**逐檔 diff 九個圖示**：

```
form-bread 同步 / form-hotpot 同步 / form-light 同步 / form-meat 同步
form-noodles 同步 / form-rice 同步 / form-snack 同步 / form-unknown 同步
⚠️ form-soup 不同步
```

跟你逐檔比對的結果一致，只有那一個。同步後再跑一次，九個全綠。

### 實機確認

「湯的」的圖示只有兩道菜會用到（`廣東粥`、`韓式人參雞湯` —— 其餘帶「湯的」的菜
都被優先序更高的吃法接走了），所以我用條件把它們逼進清單：
**「韓式人參雞湯」現在是碗裡插一支湯匙，不是放大鏡。**

---

## 三、驗證

### ✅ 實測過

| 項目 | 結果 |
|---|---|
| 靜止態沒有尖角 | ✅ 放大截圖，每一列右緣齊平 |
| 滑開態沒被改壞 | ✅ 放大截圖，動作色塊仍貼齊容器右緣並被圓角裁切 |
| 新的湯匙圖示 | ✅ 「韓式人參雞湯」實機顯示新圖 |
| 九個圖示同步 | ✅ 逐檔 diff |
| 建置與單元測試 | ✅ 51 個全過 |

### ⚠️ 已實作，未實測

沒有新增的項目。上一輪列的那三項（真的用手指左滑、滑過 200 的觸發、與捲動的競合）
你已經實機驗過通過了。

---

## 四、Commit 計畫（等你驗過）

```
FoodRotate/Views/TagGrid.swift                          （新增）
FoodRotate/Views/FilterBar.swift                        （改）
FoodRotate/Views/FoodCardList.swift                     （改）
FoodRotate/Views/FoodEditorView.swift                   （改）
FoodRotate/Assets.xcassets/icon-form-soup.imageset/     （改：同步設計新版）
FoodRotateTests/RowSwipeTests.swift                     （新增）
```

`Design/icons/form-soup.svg` 是設計的檔，也在工作區裡有變更，
要不要跟這筆一起進由你決定。

`FoodPicker.swift` 與其餘測試檔仍然零變更。
