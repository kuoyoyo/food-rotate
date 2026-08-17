# 工程回覆 — S6 第一批：身分機制與 P0-1（給 PM）

**日期**：2026-08-17 ／ **提出**：程式設計師
**依據**：`Coder/PM派工-S6-工程.md` 第一節
**狀態**：**身分機制 + P0-1 做完，紅→綠有證據。P1-1／1-2／1-3 還沒動** —— 你說機制要不要先討論一輪，我把它做出來給你看再問。

---

## 一、身分機制：一份，兩邊共用

`FoodRotate/Core/Generation.swift`（新檔，62 行，純 Foundation）

```swift
struct Generation: Equatable, Sendable { ... }   // 號碼牌
struct GenerationSource: Sendable {              // 發號機
    mutating func next() -> Generation           // 開新的一輪
    func isCurrent(_ g: Generation) -> Bool      // 你還算數嗎
    mutating func invalidate()                   // 全部作廢，但不開新的一輪
}
```

用法固定三步，轉盤與搜尋一模一樣：

```swift
let run = runs.next()                        // 1. 發動時領號碼
await something()
guard runs.isCurrent(run) else { return }    // 2. 每個 await 之後問一次
commit(result)                               // 3. 確認還算數才寫進狀態
```

### 為什麼要有它，而不是只用 `Task.isCancelled`

**取消是「請你停下來」，號碼牌是「就算你沒停下來也不算數」。**
已經越過最後一個檢查點的工作還是會把結果寫出去 —— 網路回呼尤其如此，
`URLSession`／`MKLocalSearch` 的完成處理不會因為你取消了 Task 就不執行。

`invalidate()` 跟 `next()` 分開是刻意的：`reset()` 與切換模式要的是
「停下來就好，不要再開始」，那時候不該有人持有現在的號碼。

---

## 二、P0-1：紅 → 綠

### 先讓它紅（這是這一階段的重點）

我先只做**可注入的等待**（把 `Task.sleep` 換成一個可替換的函式），不動任何邏輯，
然後寫測試。測試用一個閘門控制「誰先醒來」，所以那個競態不是碰運氣，是**指定的順序**。

跑起來是這樣：

```
◇ Test "同一輪只會結束一次" started.
✔ Test "同一輪只會結束一次" passed after 0.064 seconds.
Swift/ContiguousArrayBuffer.swift:692: Fatal error: Index out of range
2026-08-17 02:53:21.630651+0800 FoodRotate[85362:22240072] Fatal error: Index out of range
Restarting after unexpected exit, crash, or test timeout
	WheelSpinnerRaceTests.舊的一輪不能影響新的一輪()
	WheelSpinnerRaceTests.快速操作五十次()
	WheelSpinnerRaceTests.reset之後舊的一輪不得復活()
** TEST FAILED **
```

**`Index out of range` —— QC 指控的那個崩潰，在測試裡重現了。**
（它是 trap 不是例外，所以整個測試行程被打斷，後面兩支根本沒機會跑。
「紅的時候是什麼樣子」就是這個樣子。）

### 修了什麼

| 位置 | 改動 |
|---|---|
| `WheelSpinner` | 收尾工作存進 `finishTask`，`spin()` 與 `reset()` 都先取消它 |
| `WheelSpinner` | 每輪 `runs.next()` 領號碼，`finish(run:)` 驗號碼才收尾 |
| `RotateViewModel.spin` | 記 **`FoodItem.id`**，完成時 `first(where:)` 找回來；找不到就整個放棄 |

### 現在

```
✔ Test "上一輪醒來時不得結束新的一輪，也不得執行自己的 completion" passed
✔ Test "reset 之後沒有再起轉，舊的一輪醒來不得復活任何狀態" passed
✔ Test "同一輪只會結束一次" passed
✔ Test "快速「起轉 → 改格數 → 再起轉」50 次不得崩潰，也不得抽出不在清單裡的菜" passed
✔ Test run with 47 tests in 8 suites passed
```

43 → 47。**既有 43 支一個字沒改。**

---

## 三、⚠️ 兩件我不想含糊帶過的事

### 1. 取消與號碼牌，各自單獨都足以讓測試綠

你在派工單裡要了兩樣：可取消的 `finishTask` **和**每輪 generation。兩樣我都做了，
但我做了兩個對照實驗：

| 實驗 | 結果 |
|---|---|
| 兩樣都沒有（原始碼） | 🔴 **崩潰** |
| 只留取消，拿掉號碼牌 | ✅ 47 支全過 |
| 只留號碼牌，拿掉兩處取消 | ✅ 47 支全過 |
| 兩樣都留（現在） | ✅ 47 支全過 |

**所以我的測試證明的是「需要其中一樣」，不是「兩樣都必要」。**

### 2. 而且號碼牌在轉盤這邊**目前一次都沒有真的擋下任何東西**

我沒有只用推論。我暫時加了一行 `print`，在「還在轉、但號碼過期」時印出來，
跑完整組測試（含 50 次快速操作）：

```
號碼牌實際擋下的次數：0
```

原因是 `spin()` 與 `reset()` 都會先取消，而 `finish` 前面那道
`guard !Task.isCancelled` 在 MainActor 上跟 `reset()` 是不會交錯的 ——
過期的工作在更早的地方就回頭了，走不到號碼牌那一關。

> 這跟你定的「**不要留著一段不會生效的程式碼**」有張力，所以我攤開來講，不自己決定。

**我的建議是留著**，兩個理由：

1. 它是**要拿去搜尋那邊用的同一份機制**。搜尋端取消救不了 ——
   `MKLocalSearch` 的結果回來時 Task 早就過了最後一個檢查點，
   那裡的號碼牌一定會真的擋下東西。轉盤這邊留著，兩邊的形狀才一致。
2. 它擋的是崩潰，成本是一個 `guard` 加一行註解。

**但如果你認為「轉盤這邊擋不到就不該留」，我拿掉，只留取消。** 說一聲就好。

### 3. `FoodItem.id` 那一層我做不出會紅的測試

號碼牌修好之後，過期的那一輪**根本不會醒來執行**，所以「拿舊位置讀新清單」
這件事再也發生不了 —— 我試不出能讓它紅的情境（每一條會改變清單的路徑
：改格數、換一組、拿掉一道，都會先呼叫 `spinner.reset()`）。

**所以那一層是防禦深度，不是有測試背書的修正。** 我照樣做了，因為它幾乎零成本，
而且它保護的是不同的東西：號碼牌管「哪一輪算數」，id 管「算數的那一輪講的是哪一道菜」。
但我不會把它算進「已驗證」那一欄。

---

## 四、為了寫測試做的兩處注入（P3-1 的最小切片）

| 注入 | 為什麼現在就要 |
|---|---|
| `WheelSpinner.Wait`（等待改成可替換的函式，預設仍是 `Task.sleep`） | 不能控制「什麼時候醒來」就寫不出這一批的紅測試 |
| `RotateViewModel(spinner:)` | 50 次快速操作那支要從 view model 這一層跑，才踩得到 `items[index]` |

兩個都有預設值，**正式路徑的行為完全沒變**。你把「抽成可注入的小介面」排在第三批，
但第一批沒有它就沒有證據，所以我先切了最小的一塊過來。

---

## 五、紅線檢查

| 紅線 | 狀態 |
|---|---|
| `FoodPicker.swift` 零變更 | ✅ 沒碰 |
| 八條產品規則行為零變化 | ✅ 抽樣、放寬、忌口一律沒動；改的只有「什麼時候算數」 |
| 既有 43 支不准為了讓它過而改 | ✅ 一個字沒改，43 → 47 是純新增 |
| 每一項修正都要有先紅過的測試 | ✅ P0-1 有（見第二節）／⚠️ id 那一層沒有，理由見三-3 |

---

## 六、還沒動的，以及我要問的

**P1-1／P1-2／P1-3 我還沒開始。** 你說「請先決定一套做法再動手」，
機制我做出來了，也在最會崩的那一項上驗過。**在往搜尋端鋪之前，先問你兩件事：**

1. 第三節那個號碼牌 —— 轉盤這邊留還是拿掉？
2. `Generation` 這個形狀你認可嗎？（`next` / `isCurrent` / `invalidate` 三個動作）
   搜尋端我打算這樣用：切 source → `invalidate()` + `nearby.stop()`；
   每次搜尋 → `next()`；`apply` 同時驗號碼與 `source == .restaurants`，
   而且**結果由參數帶進來**，不從共享的 `nearby.phase` 讀。

你點頭我就往下做，不動的話我明天就照這個形狀鋪完三項。

P1-4 的視覺補充（餐廳紀錄不加任何視覺差別、只是不顯示還原圖示）我收到了，
第二批照做 —— 那跟 S5-B 的「沒有那個資訊就不畫那個位置」是同一條，不用改規格。

---

## 七、Commit 計畫（等你回覆）

```
FoodRotate/Core/Generation.swift              （新：身分機制，兩邊共用）
FoodRotate/Views/WheelView.swift              （改：finishTask + 號碼牌 + 可注入等待）
FoodRotate/Views/RotateView.swift             （改：spinner 可注入、記 id 不記位置）
FoodRotateTests/WheelSpinnerRaceTests.swift   （新：4 支，其中 1 支修前會崩）
```

`Design/` 底下那批（設計的 17／24／48pt 渲染腳本）是設計自己的，我沒碰，另外一筆。
