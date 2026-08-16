# PM 派工 — S6 硬化（程式設計師）

**日期**：2026-08-16 ／ **派工**：PM
**基準**：`12cbda6`
**總規劃**：`PM/PM規劃-S6依QC報告.md`（裁示與理由在那裡，本單是執行版）
**原始報告**：`QC專案健康檢查報告-2026-08-16.md`

---

## 〇、這一階段跟前五個都不一樣

S1–S5 改的是看得見的東西，**S6 改的全是看不見的**：競態、過期結果、送審合規。

有一個直接的後果：**你這次沒辦法用截圖證明修好了。**
上一輪你說「我沒有工具做觸控」，這一輪的問題是「就算有觸控也拍不到」——
P0-1 那個崩潰不會出現在任何一張截圖裡。

**所以這一階段的證據形式改成測試。** 每一項修正都要有一支會紅的測試。

---

## 一、第一批：非同步邊界（P0-1、P1-1、P1-2、P1-3）

### ⚠️ 先想清楚再動手

這四項的共同根因是同一件事：**沒有辦法分辨「這個結果屬於哪一次請求」。**

轉盤需要 generation token，搜尋需要 request ID，**本質是同一個機制**。
請先決定一套做法，不要四個地方各做一套 —— 那是下一個競態的溫床。

### P0-1 轉盤完成 Task（唯一會崩潰的一項）

`WheelView.swift:40` 那個 `Task {}` 沒有被保存，所以 `reset()`（:57）取消不了它；
`finish()`（:66）只 `guard isSpinning`，分不出目前轉的是哪一輪。

我照 QC 的重現步驟讀過控制流，**指控成立**：舊 Task 醒來看到新一輪的
`isSpinning == true`，就把新一輪提前結束，並用**舊的 index** 去讀現在的 `items`。
新清單較短就是 array out of range。

| 要做 | |
|---|---|
| 可取消的 `finishTask` | 每次 `spin` 前與 `reset()` 都取消 |
| 每輪唯一的 generation | 醒來後確認 token 仍是這一輪才執行 |
| `RotateViewModel.spin` 捕捉 **`FoodItem.id`** 而不是只捕捉索引 | 完成時驗證清單仍含同一 ID |

**測試（必加，而且要先讓它紅）**：reset A → 啟動 B → A 到點不得影響 B；
新清單較短時不得崩潰；只有 B 的 completion 能執行一次。

### P1-1／P1-2 搜尋的過期結果與被忽略的新條件

- 切回「吃什麼」時沒有 `nearby.stop()`，舊搜尋回來會把餐廳結果寫進 `allItems`
- `findRestaurants()` 的 `guard !isLoading else { return }` 會**直接忽略載入中的新條件**

第二項尤其要修：**使用者看到新菜系已經選中，拿到的卻是舊搜尋的結果** ——
那正是「不假裝」原則要防的事。

| 要做 | |
|---|---|
| 切 source 時取消舊搜尋、結束對應的 Live Activity 與 background task | |
| 每次搜尋建 request ID，`apply` 同時驗 request ID 與 `source == .restaurants` | |
| `apply` 接受結果本身 | 不要再從共享的 `nearby.phase` 讀，那可能已被下一個請求改掉 |
| 新條件到來時**取消舊搜尋並重啟**，不是忽略 | 可加 200–300ms debounce |

### P1-3 `placemarkNotFound` 跳過 fallback

fallback 只在 `places.isEmpty` 時執行（`NearbySearch.swift:209`），
但 `MKLocalSearch` 找不到店家時會**拋錯**，直接跳到 :229 的 catch，繞過 fallback。

多詞搜尋同樣受害：「東南亞」查「泰式」＋「越南料理」，
**第一個找到了、第二個 throw，整批結果一起丟掉。**

| 要做 | |
|---|---|
| 把 `placemarkNotFound`／`directionsNotFound` **正規化成該搜尋詞的空結果** | |
| 多詞逐詞處理 | not-found → continue；server failure／throttle／decode failure 才考慮中止 |
| 所有詞都無結果後才做一般「餐廳」搜尋並設 `didFallBackToGeneric` | |

**測試**：單詞 not-found 會 fallback；第二詞 not-found 不抹掉第一詞結果；
服務端錯誤不得被誤當成「沒有店」。

### 第一批的驗收門檻

**快速操作 50 次無崩潰；切模式後舊結果不回灌；改條件只接受最後一次請求；
單一搜尋詞找不到不會抹掉其他有效結果。**

---

## 二、第二批：資料正確性與送審

### P1-4 餐廳歷史 —— **我已裁示：只展示，不還原**

理由在 `PM/PM規劃-S6依QC報告.md` 第二節。摘要：保存下來的餐廳資料會過期，
「還原」出一份可能已經不存在的清單是另一種假裝知道；而現在那個還原按鈕**是死的**，
死按鈕跟靜默退回是同一種病。

| 要做 | |
|---|---|
| `SpinRecord` 新增 `source` | 沒有它連「要不要顯示還原」都判斷不了 |
| `SpinRecord` 新增 **`winnerID`** | 連帶解掉 P2-4 的一半，名稱只作顯示 |
| 歷史列依 source 決定是否顯示還原圖示 | **餐廳紀錄不顯示** |
| SwiftData migration | 舊紀錄沒有 source／winnerID，要能降級用名稱解析 |

**測試**：料理紀錄／餐廳紀錄／舊版紀錄三類。

### P1-5 `PrivacyInfo.xcprivacy` —— 這是上架硬門檻

沒有它送不上去，不是品質問題。

⚠️ **不要照抄別人的 manifest。** QC 特別寫了「應由負責送審的人核對是否適用
Apple 列出的 `CA92.1`，不可直接照抄而不審核」——這一條照做。

| 要做 | |
|---|---|
| 新增合法的 `PrivacyInfo.xcprivacy` 到 App target resources | |
| 宣告 UserDefaults 的正確 required reason | 逐條對 Apple 文件核對 |
| 確認定位資料有沒有被收集，如實填 data collection | |
| Archive 後產 privacy report，確認主 App 與 extension 的合併結果 | |

### P2-1 距離文案

`NearbySearch.swift:218`、:277 寫死「十五公里」，實際上限來自設定（預設 5、上限 10）。

> **這一條你自己的註解就抓到了**：`:432` 寫著「一度寫死十五公里，但那對『現在要去吃飯』
> 來說太遠了」。**決定改了，文案沒跟著改。** 這種缺陷讀 diff 抓不到，只有整檔通讀才會發現。

改法：統一走 `SearchRadius.label(AppSettings.shared.searchRadius)`，
所有錯誤與 empty state 只讀同一個距離來源。**四種半徑各加一支文案測試。**

### P2-2 地圖視窗固定 2.5 公里

搜尋接受 10 公里內的結果，但 map camera 永遠 2,500m，遠的 marker 落在視窗外。
用位置＋所有結果算 bounding region，或至少依 `searchRadius` 設 span；
**結果更新時也要更新**，不能只靠 `onAppear`。

### P2-3 自訂料理改名有兩套真相來源

轉盤改名寫 `renamedNames`，但「我的清單」直接列 `customItems` 不套 override，
**同一道菜在兩個畫面可能顯示不同名字**。而且 `update(item)` 前先呼叫 `rename`，
此時 store 還是舊名，反而留下新的 override。

改法：**自訂料理只保留一個名稱真相來源** —— 直接更新 `customItems`，
`renamedNames` 只服務不可修改的內建料理。或提供 `resolvedCustomItems` 兩頁共用，
**不能一頁讀 raw、一頁讀 resolved**。

### P2-4 名稱被當成身分

第二批的 `winnerID` 做完之後，把 `FoodCardList` 與 `HistoryView` 的
`item.name == winnerName` 換成 ID 比對。

---

## 三、第三批：回歸防線

### P3-1 測試覆蓋

現在 43 個測試集中在純函式層，**風險最高的狀態層一支都沒有**。照 QC 的順序：

1. 先把 MapKit、時間、隨機數、持久化、Live Activity 抽成可注入的小介面
2. 狀態機單元測試：取消、過期 callback、快速切模式、重複搜尋、reset/spin race
3. 整合測試：餐廳歷史保存／還原、UserDefaults 重啟一致、SwiftData save failure
4. 少量 UI tests：首次啟動、兩模式切換、轉動中換條件、歷史還原、深淺關鍵頁

### P2-5 SwiftData 降級靜默

container 建立失敗會退回記憶體，儲存用 `try?` —— **使用者以為存了，重啟就沒了**。
保持可啟動的降級，但把「歷史暫時無法保存」當成非阻擋提示顯示；
至少用 `Logger` 記錄失敗。

### P3-2 驗收證據不可重現

**這一條也是我的問題**（我一路把截圖放 `/private/tmp/`）。
往後：精簡的驗收附件進 repo，或保存產圖腳本與操作步驟。

---

## 四、⚠️ 這一階段的紅線

前五階段的紅線是「不改行為」。**S6 反過來 —— 這一階段就是要改行為。**

所以紅線變成：

| 紅線 | |
|---|---|
| **`FoodPicker.swift` 仍然零變更** | 抽樣邏輯沒有出現在 QC 的任何一項問題裡。它從 S1 到現在一行未改，S6 也不該碰 |
| **八條產品規則行為零變化** | 修競態不該改變「抽到什麼」，只該改變「什麼時候算數」 |
| **既有 43 個測試不准為了讓它過而改** | 這條從 S4 沿用 |
| **每一項修正都要有一支先紅過的測試** | 見第五節 |

---

## 五、證據形式改成測試（這一階段最重要的一條）

你在 S4 的左滑學到「沒辦法實測的東西，至少要確認它在原理上會生效」，
在 S5 的 id 修正學到「先讓探針在錯的版本上亮紅燈，才相信它的綠燈」。

**這一階段把後者變成標準做法**：

> 每一項修正，先寫一支在**修之前會紅**的測試，再修到它綠。
> 報告裡附上「紅的時候是什麼樣子」。

理由：S6 的缺陷都是狀態競態，**它們在正常操作下不會出現** ——
沒有一支會紅的測試，我沒有辦法分辨「修好了」跟「剛好沒踩到」。

---

## 六、驗收（S6 完成的判準）

1. P0 全清
2. P1 全清（P1-4 已裁示為替代行為）
3. 43 個既有測試持續通過，**且新增非同步／歷史／持久化測試**
4. Debug、Release、archive 均成功
5. Privacy report 與 App Store validation 通過
6. 實測：快速換條件、切模式、定位拒絕、定位逾時、無搜尋結果、fallback、
   餐廳歷史、深淺模式、reduce motion
7. **入口文件反映最新狀態**（`PROJECT_STATUS.md`，我會先建好）

---

## 七、兩條規矩（不變）

1. **任何 git 操作前先向 PM 匯報**
2. 表格只有兩種標記：**✅ 實測過** 與 **⚠️ 已實作、未實測**，
   而「已實作」的前提是**確認它在原理上會生效**
