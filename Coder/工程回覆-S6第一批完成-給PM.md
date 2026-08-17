# 工程回覆 — S6 第一批完成（P1-1／P1-2／P1-3）

**日期**：2026-08-17 ／ **提出**：程式設計師
**依據**：`Coder/PM派工-S6-工程.md` 第一節、你對身分機制的兩項裁示
**狀態**：**第一批四項全部做完，紅→綠都有證據。未 commit。**

---

## 〇、先回答你的狀態問題

我沒有卡住，也沒有在等回覆 —— 你的裁示到之前我就照那個形狀往下做了（你看到的檔案異動就是）。
**04:12 到 08:17 那段沒有新檔案異動，是因為我在反覆跑測試追一個 flaky。**

那件事本身值得寫進報告，見第四節。

---

## 一、三項的改法

### P1-3 多詞搜尋容錯（`NearbySearch.swift`）

「找不到店」與「服務掛了」在型別上都是 throw，**分界線收在一個地方**：

```swift
static func isNotFound(_ error: any Error) -> Bool   // placemarkNotFound / directionsNotFound
```

逐詞處理：not-found → 這個詞貢獻 0 家、繼續下一個；服務端錯誤 → 記下第一個、繼續下一個。
回傳 `TermSearchOutcome(places:hardFailure:)`。

上層據此分三條路：

| 情況 | 行為 |
|---|---|
| 有結果 | 給結果（就算某個詞掛了也不丟掉已經拿到的） |
| 全空、**沒有**硬錯誤 | 做一般餐廳 fallback，並記 `didFallBackToGeneric` |
| 全空、**有**硬錯誤 | **不 fallback**，照實說服務出事 |

第三條是新的：以前服務掛掉會被說成「附近沒有餐廳」，然後用一個猜的 fallback 蓋過去。
**那是在假裝知道一件我們其實不知道的事。**

### P1-2 載入中改條件不再被忽略（`RotateView.swift`）

`guard !isLoading else { return }` 拿掉，改成 `abandonSearch()` 之後重開一次。
**慢一點沒關係，給錯答案不行。**

### P1-1 切模式停掉舊搜尋

`source` 的 didSet 加 `abandonSearch()`：作廢號碼、`nearby.stop()`、收掉 Live Activity 與背景時間。

### 結果由參數帶進來

`searchRestaurants` 多一個 `onFinish`，帶 `RestaurantSearchOutcome`。
`apply(outcome:run:startedAt:)` **不再讀 `nearby.phase`** ——
照你說的，從共享狀態讀等於驗了等於沒驗。

`NearbySearchModel` 那邊也收斂成**一個終點**（`finish(_:onStage:onFinish:)`）：
`phase`（給「附近的店」那一頁）與回呼（給轉盤那一頁）在同一個地方用同一份資料寫出去，
兩邊不可能對不起來。

---

## 二、紅 → 綠

### P1-3（修之前）

```
✘ "第二個搜尋詞找不到店，不得抹掉第一個詞已經找到的結果"
    Caught error: Error Domain=MKErrorDomain Code=4     ← placemarkNotFound 直接炸出來
✘ "唯一的搜尋詞找不到店，是「沒有店」不是錯誤"
    Caught error: Error Domain=MKErrorDomain Code=4
✘ "服務端錯誤不得被當成「附近沒有店」"
    Caught error: Error Domain=MKErrorDomain Code=2
✘ "有結果的詞成功、另一個詞服務端錯誤時，結果留著"
    Caught error: Error Domain=MKErrorDomain Code=3
```

第五支（合併後照距離排序）修前修後都綠 —— 它是回歸防線，不是這次的證據，我不算它。

### P1-1／P1-2（修之前）

```
✘ "切回「吃什麼」之後，還在路上的餐廳搜尋不得把結果灌進清單"
    Expectation failed: model.allItems.allSatisfy { !$0.id.hasPrefix("place-") }
✘ "載入中改條件不得被忽略，最後生效的必須是最後一次請求"
    Expectation failed: secondRequestWasMade          ← 第二次請求根本沒發出去
    Expectation failed: (names → ["餐廳的店"]).contains(where: { $0.contains("韓") })
✘ "後到的舊請求不得覆蓋新請求的結果"
    Expectation failed: await gate.waitUntilArrived(2)
```

### 現在

```
✔ Test run with 55 tests in 10 suites passed
```

43 → 55（+4 轉盤、+5 多詞容錯、+3 搜尋競態）。**既有 43 支一個字沒改。**

### 我又做了一次拆開驗（照上一輪的做法）

因為測試在中途改過形狀，最早那次紅不能代表最終的測試，所以**用最終版的測試重跑兩個對照**：

| 拿掉哪一半 | 結果 |
|---|---|
| 復原 `guard !isLoading`（P1-2 的 bug） | 🔴 兩支紅，訊息精準：「第二次請求根本沒發出去」、清單裡是 `["日式的店"]` |
| 復原「切模式不停搜尋」＋拿掉模式檢查（P1-1 的 bug） | 🔴 一支紅：`place-` 開頭的項目跑進菜色清單 |
| 全部修好 | ✅ 55 支全過 |

**這次號碼牌不是冗餘的。** 上一輪在轉盤那邊它一次都沒攔到（取消更早一步）；
搜尋這邊不一樣 —— `abandonSearch()` 之後舊的 Task 可能已經越過檢查點，
號碼牌是真的在擋。

---

## 三、⚠️ 一個超出派工單的行為改動，請你看一眼

`LoadingActivityController` 我加了 `cancel()`。

原本只有 `end(stage:)`。切模式／改條件時如果用它收尾，只能傳 `.failed` ——
**鎖定畫面上會留一張寫著「失敗」的卡四秒，但沒有任何事情失敗，是使用者改變主意。**

把使用者的取消說成失敗，跟把「附近沒有店」說成「服務故障」是同一種錯，所以我分開：
`cancel()` 讓那張卡立刻消失、不留終態。

這是**新增的行為**，不在派工單裡。要退回的話說一聲，我改成沿用 `end(stage: .failed)`。

---

## 四、⚠️ 我自己寫的測試是 flaky 的，我花了三個多小時把它修掉

這件事必須講，因為它差一點就變成「我交了一組會隨機紅的測試」。

### 症狀

同一份程式碼，整組跑五遍 —— **四遍紅、一遍綠**。而且單獨跑那個 suite 跟跟著全部跑，結果不一樣。

### 兩個原因，都是我自己造成的

**1. 測試本身有競態。**
`model.source = .restaurants` 這個動作**自己就會打一次搜尋**（那時還沒有菜系，查的是「餐廳」）。
我原本寫成「先切模式、再設條件」，於是「第一個抵達閘門的是哪一個請求」不確定。
改成**條件先設好再切模式**，抵達順序就變成固定的 `["日式", "韓式"]`。

**2. `Task.yield()` 的忙迴圈不會讓剛建立的工作排進來。**
我原本用「讓 2000 次」當等待，想避開「睡一個猜的秒數」。結果反過來 ——
那個迴圈一直把自己排回佇列，**新建立的 Task 一次機會都拿不到**，等 2000 次也等不到。
真的 `Task.sleep(for: .milliseconds(1))` 才會讓出執行機會。

現在所有等待都是**輪詢一個條件 + 上限兩秒**：快的機器立刻回來，慢的機器多等一下，
兩者都不是在賭。兩個 suite 也都標了 `.serialized`。

### 現在的穩定度

**連續四次完整跑全綠**（55 支，`recorded an issue` 計數 0）。

⚠️ 但我要講清楚：**四次全綠是觀察，不是「已證明不會 flaky」。**
非同步測試的穩定性沒辦法用有限次數證明。如果你在自己的機器上看到偶發紅，
那是我的測試還不夠穩，回報給我，不要當成程式壞了。

> 這一條我想記下來：**偶爾紅的測試比沒有測試更糟** —— 它會訓練人忽略紅燈，
> 而真的那次也會一起被忽略。跟 S5 那個「固定噴假警報的檢查等於沒有檢查」是同一件事。

---

## 五、為了測試新增的注入（都有預設值，正式路徑行為不變）

| 注入 | 為什麼 |
|---|---|
| `NearbySearchModel.TermQuery` | 「第二個詞找不到」這種情境跟網路無關，但不注入就只能靠 MapKit 剛好回什麼 |
| `NearbySearchModel.LocationProvider` | 測試環境沒有定位權限，不注入的話整條搜尋在第一步就停住 |
| `RotateViewModel(nearby:)` | P1-1／P1-2 是 view model 這一層的狀態機 |

加上上一輪的 `WheelSpinner.Wait` 與 `RotateViewModel(spinner:)`，一共五個注入點。
**這是 P3-1「抽成可注入的小介面」的實際進度** —— 你排在第三批，但第一批沒有它就沒有證據。

---

## 六、紅線檢查

| 紅線 | 狀態 |
|---|---|
| `FoodPicker.swift` 零變更 | ✅ 沒碰 |
| 八條產品規則行為零變化 | ✅ 抽樣與放寬邏輯沒動。改的是「什麼時候算數」與「錯誤怎麼分類」 |
| 既有 43 支不准為了讓它過而改 | ✅ 一個字沒改 |
| 每一項修正都要有先紅過的測試 | ✅ P1-1／P1-2／P1-3 都有，見第二節 |

---

## 七、第一批的驗收門檻

| 門檻 | 狀態 |
|---|---|
| 快速操作 50 次無崩潰 | ✅ 有一支測試就是跑 50 次（上一輪交的） |
| 切模式後舊結果不回灌 | ✅ 有測試，拿掉修正會紅 |
| 改條件只接受最後一次請求 | ✅ 有測試，拿掉修正會紅 |
| 單一搜尋詞找不到不會抹掉其他有效結果 | ✅ 有測試，拿掉修正會紅 |

⚠️ **這四項我都沒有實機操作過。** 這一批是狀態機的事，測試是比實機更精準的證據
（實機沒辦法讓我指定「舊請求在新請求之後才回來」），但**實機仍然可能有我沒想到的路徑** ——
例如真的網路延遲下 Live Activity 的收尾時機。你要實測的話，值得試的是：
搜尋中連續改三次菜系、搜尋中切模式、搜尋中按 home 再回來。

---

## 八、Commit 計畫（等你驗過）

```
FoodRotate/Core/Generation.swift                      （新：身分機制）
FoodRotate/Views/WheelView.swift                      （改：P0-1）
FoodRotate/Views/RotateView.swift                     （改：P0-1 的 id、P1-1、P1-2）
FoodRotate/Services/NearbySearch.swift                （改：P1-3、結果由回呼帶出）
FoodRotate/Services/LoadingActivityController.swift   （改：新增 cancel()，見第三節）
FoodRotateTests/WheelSpinnerRaceTests.swift           （新：4 支）
FoodRotateTests/NearbySearchTermsFaultTests.swift     （新：5 支）
FoodRotateTests/RestaurantSearchRaceTests.swift       （新：3 支）
```

你說 commit 等第一批完整 —— 現在完整了。`Design/` 底下設計的渲染腳本我沒碰。

第二批（P1-4 餐廳歷史、P1-5 PrivacyInfo、P2-1 距離文案…）我還沒開始，等你這一批驗完再開。
P1-4 的視覺補充（不加任何視覺差別、只是不顯示還原圖示）已經收到。
