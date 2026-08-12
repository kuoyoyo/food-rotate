# 工程回覆 — 刪掉一道之後狀態黏在位置上

**日期**：2026-08-13 ／ **提出**：程式設計師
**依據**：`Coder/PM驗收-捲不動回歸-通過但發現一項.md` 第三節
**狀態**：修完。未 commit

---

## 一、改動：一行

`FoodCardList.swift`

```swift
- ForEach(Array(items.enumerated()), id: \.offset) { index, item in
+ ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
```

索引仍然拿得到，繼續用來畫列與列之間的分隔線 —— **位置歸位置，身分歸身分**，
這一行之前是把兩件事混成一件。

### `item.id` 在同一份清單裡不會撞號，這是我確認過的

你要我先確認再用，三個來源都查了：

| 來源 | id | 會不會撞 |
|---|---|---|
| 內建 `foods.json` | 手寫 slug（`beef-noodle-soup`） | 不會。`FoodDataAudit.duplicateID` 盯著，而且 `FoodDataAuditTests` 是**對真實的 `FoodLibrary.all` 斷言零問題**，不是只測假資料 |
| 自訂料理 | `custom-<UUID>`（`CustomFoodStore.swift:64`） | 不會 |
| 附近店家 | `place-<UUID>`（`NearbySearch.swift:67`） | 不會。而且 `RotateView.swift:212` 是用 `Dictionary(uniqueKeysWithValues:)` 收的，真撞號那裡會先崩 |

再加一層：`FoodPicker` 逐層放寬時是用 `seen.insert($0.id).inserted` 去重
（`FoodPickerTests` 第 4 支「放寬多層時…且不重複收同一道菜」就在測這件事）。
**所以「同一份清單不會有兩個相同 id」這個前提已經有測試守著，我沒有再補一支重複的。**

你提的「店家 id 每次搜尋都新生」我想過：那影響的是**跨搜尋**的穩定性，
但重新搜尋時整份清單本來就全換，每一列都該是新的。`ForEach` 要的是
「同一份清單存續期間內唯一且不變」，UUID 滿足這個條件。

---

## 二、✅ 這次我有實機證據，不是「原理上會生效」

上一張單我自己承認自證比較弱。這一項我找到取證的方法了。

### 探針

暫時在每一列加一個 `@State birthName`，記下**這個 view 實例誕生時顯示的是哪道菜**，
再把它跟當下的 `item.name` 比：一樣顯示綠色 `＝`，不一樣顯示紅色 `✗舊菜名`。
不一樣就等於「SwiftUI 把舊狀態接到新資料上了」—— 那正是這個 bug 的定義。

再暫時加一個 4 秒後自動刪掉第 3 道的 `.task`（我沒有手指，但刪除可以用程式觸發），
以及 `.defaultScrollAnchor(.bottom)` 把清單頂到畫面上。

### 兩次對照

| 版本 | 刪掉第 3 道（印尼炒飯）之後 |
|---|---|
| **故意退回 `id: \.offset`** | 🔴 **第 1、2 列綠色，第 3 列到第 11 列全部紅字**：「美式漢堡 ✗印尼炒飯」、「越式河粉 ✗美式漢堡」、「美式烤肋排 ✗越式河粉」…**整串往上錯開一格** |
| **`id: \.element.id`** | ✅ **11 列全部綠色 `＝`**，每一列還是它自己誕生時那道菜 |

第一列那個紅字鏈就是你在實機上看到的現象的機制本身：刪除點以後的每一列都
接到了下一道菜，狀態卻留在原位。**刪除點之前的兩列不受影響**，也跟你觀察到的一致。

> 這也順便證明**探針有牙**。我先讓它在錯的版本上亮紅燈，才相信它在對的版本上的綠燈。

### 收尾

三段暫時的東西（`birthName` 與標記、自動刪除的 `.task`、`.defaultScrollAnchor`）
全部移除，`grep 暫時` 在 `FoodRotate/` 底下只剩 `NearbySearch.swift` 兩句原本就有的
錯誤訊息文案。`RotateView.swift` 的 `git diff` 是空的。

| 項目 | 結果 |
|---|---|
| 刪除後每列狀態跟著自己的菜 | ✅ 實機取證（上表） |
| 靜止態版面 | ✅ 乾淨，探針無殘留 |
| 建置與單元測試 | ✅ 43 個全過 |

---

## 三、我順手查了同一類缺陷還在哪裡，但沒有動

用索引當身分只有在「清單會變動」且「列自己持有狀態」時才出問題。全庫掃了一遍：

| 位置 | 判斷 |
|---|---|
| `FoodCardList.swift:311`、`ResultSheet.swift:247`（優缺點條目） | 安全。純顯示、沒有 `@State`、渲染期間不會變動 |
| `FoodEditorView.swift:122`（`ForEach(points.indices, id: \.self)`） | ⚠️ 同樣用索引，但只有「再加一則」沒有刪除，而且列裡沒有 `@State`（`TextField` 直接綁 `points[index]`）。**現況不會錯位**，但如果之後加了刪除就會 —— 而那是 S5-B 以後的事 |

`FoodEditorView` 我**沒有改**。它現在沒有壞，而你說過「不要順手做」。
寫在這裡是為了讓它有紀錄，要不要動由你排。

---

## 四、你說先不要補的那項，我沒有補

「滑開之後點列不會收回」維持現況，等你看完實機再決定。

---

## 五、Commit 計畫（等你驗過）

```
FoodRotate/Views/FoodCardList.swift                  （改：巢狀水平 ScrollView + 身分改用 item.id）
FoodRotateTests/RowSwipeTests.swift                  （刪：測的機制已不存在）
FoodRotate/Assets.xcassets/icon-form-meat.imageset/  （改：同步肉食 v5）
```

上一張單的改動還沒 commit，這一行併進同一筆 —— 兩者是同一次修的同一塊程式碼，
分成兩筆會讓「左滑改寫」那一筆在歷史上是個帶著已知缺陷的中間狀態。
`Design/` 底下設計自己更新的檔另外一筆。`FoodPicker.swift` 仍然零變更。
