# 工程回覆 — S6 第二批（P1-4、P2-1～P2-4）

**日期**：2026-08-17 ／ **提出**：程式設計師
**依據**：`Coder/PM派工-S6-工程.md` 第二節、你對 P1-4 的裁示與視覺補充
**狀態**：**P1-5 以外全部做完，紅→綠都有證據。未 commit。**

P1-5（privacy manifest）照你說的**沒有動** —— 等你跟 kuoyo 確認送審端的實際狀況。

---

## 一、P1-4 餐廳歷史：只展示，不還原

### 資料

`SpinRecord` 加兩欄，都有預設值，**所以不需要 migration plan** —— 舊紀錄照樣讀得出來，缺的部分降級補上：

| 欄位 | 舊紀錄沒有的時候 |
|---|---|
| `sourceRawValue` | 用內容推：清單裡有 `place-` 前綴就是餐廳紀錄 |
| `winnerID` | 降級用 `winnerName` 找回來 |

```swift
var canRestore: Bool { resolvedSource == .dishes && !items.isEmpty }
```

**第二個條件是我加的，不在你的裁示裡**：舊版存的 JSON 少了欄位會整個解不開
（`SpinRecord.items` 回空陣列），那時候「還原」出來是一份空清單 ——
**那也是一顆死按鈕，只是死法不一樣**。既然這一項的理由就是不要死按鈕，就一起處理了。

### 畫面

- 能還原的：整列是按鈕，右邊有還原符號
- 不能還原的：**整列不是按鈕**（不是按了沒反應，是根本沒有按鈕），右邊沒有符號
- **沒有任何其他視覺差別** —— 不淡化、不加鎖、不改字色，照你的裁示

### ✅ 實機順帶驗到一件事

截圖裡有兩筆 **8/13 的紀錄**，那是這次改欄位之前存的。
它們**照樣顯示、照樣可以還原** —— SwiftData 接受了新欄位、降級路徑在真實資料上生效。
這比我自己造的假舊紀錄有力。

---

## 二、P2-1 距離文案

兩句寫死的「十五公里」拿掉，改成 `SearchRadius.label(maxDistance)`，只有一個來源。

> 你說這條諷刺 —— 同一個檔案的註解自己寫著「一度寫死十五公里，但那對『現在要去吃飯』
> 來說太遠了」。我把那段話原封不動寫進新函式的註解，讓下一個人看到「決定」與「文案」
> 是綁在一起的。

四種半徑各一支測試（`arguments: SearchRadius.allowed`），加一支「1 公里與 10 公里講的不是同一句話」。

---

## 三、P2-2 地圖視窗

`NearbyMapCamera.region(around:covering:)`：用**使用者位置 + 所有結果**算 bounding，
乘 1.35 留白，最小邊長 900 公尺。經度一度的距離隨緯度收縮，有做修正。

視窗**在結果變動時也會重算**（`onChange(of: places.map(\.id))`），不只 `onAppear`。

抽成純函式的理由跟 `isNotFound` 一樣：**這一段的正確性是可以用數字驗的**，
不該埋在 view 裡靠眼睛看。

---

## 四、P2-3 自訂料理的名字只有一個真相來源

規則定成：**`renamedNames` 只服務改不動的內建料理；自訂料理的名字就在 `customItems` 裡。**

- `rename(id:to:)` 遇到自訂料理 → 直接改它本身，順手清掉舊覆寫
- `pool` 對自訂料理**不套覆寫**（舊版留下的孤兒覆寫直接無視）
- `FoodEditorView.save` 拿掉「先 rename 再 update」

那個「先 rename」原本是要清覆寫的，實際上**反而製造了一筆覆寫** ——
呼叫它的當下 store 裡還是舊名，於是它老老實實記下了新名。測試抓到的就是這一筆：

```
✘ "編輯後儲存不會留下一筆指向新名的覆寫"
    Expectation failed: (store.renamedNames → ["custom-A00942FC…": "巷口麵線"]).isEmpty → false
```

---

## 五、P2-4 名字不再當身分

| 位置 | 改成 |
|---|---|
| `SpinRecord.winner` | 先用 `winnerID` 認，認不到才降級用名字 |
| `FoodCardList` | `winnerName: String?` → `winnerID: String?` |

有一支測試專門釘這件事：兩道同名（自訂的改成跟內建同名，使用者做得到）時，
用名字認會拿到第一個 —— **那是另一道菜**。

---

## 六、紅 → 綠

修之前（新 API 先用**舊語意**實作，讓測試跑得起來而不是編不過）：

```
✘ "餐廳紀錄不可以還原"            (record.canRestore → true) == false
✘ "解不開的舊紀錄不可以還原"       (record.canRestore → true) == false
✘ "舊紀錄沒有 source，用內容推"     (places.resolvedSource → .dishes) == .restaurants
✘ "兩道同名時，id 分得出來"        (record.winner?.id → "builtin") == "custom-1"
✘ "四種半徑各自講出自己的數字"      ("附近十五公里內找不到餐廳…").contains("3 公里")
✘ "1 公里與 10 公里講的不是同一句話"  兩句一模一樣
✘ "在轉盤上改自訂料理的名字…"       (inMyList → "阿婆麵線") == (onWheel → "巷口麵線")
✘ "編輯後儲存不會留下孤兒覆寫"      renamedNames 有一筆
✘ "舊覆寫不得蓋過自訂料理"          pool 顯示 "舊覆寫的名字"
✘ "最遠的店也要在視窗裡"            8 公里外那家落在視窗外
```

現在：

```
✔ Test run with 73 tests in 14 suites passed
```

55 → 73（+8 歷史紀錄、+2 距離文案、+6 改名、+3 地圖視窗）。**既有 43 支仍然一個字沒改。**

---

## 七、為了測試新增的注入

`CustomFoodStore(defaults:)` —— 改名規則只能拿真實讀寫來驗，但測試不該汙染使用者的偏好設定，
所以每一支測試用自己的 UserDefaults 網域。正式路徑仍是 `.standard`。

這是第六個注入點。P3-1 的清單裡「持久化」這一項因此也提前了。

---

## 八、⚠️ 我驗不到的

| 項目 | 狀態 |
|---|---|
| 菜色紀錄顯示還原符號、可以還原 | ✅ 實機截圖 |
| 舊紀錄（8/13 存的）降級後正常顯示 | ✅ 實機截圖 |
| **餐廳紀錄那一列長什麼樣** | ⚠️ **已實作、未實測**。`canRestore == false` 有測試背書，但「那一列在畫面上沒有符號」我沒看到 —— 要產生一筆餐廳紀錄得在「去哪吃」模式轉一次，那需要點按 |
| 地圖視窗框住遠處的店 | ⚠️ **已實作、未實測**。數學有測試，但實機要有一家 8 公里外的店才看得到 |
| 改名兩頁一致 | ⚠️ **已實作、未實測**。邏輯有測試，畫面沒實機走一遍 |

**這三項都需要點按，我沒有工具。** 你實測的話值得走的順序：
「去哪吃」轉一次 → 看歷史那一列 → 回設定改一道自訂料理的名字 → 看轉盤與我的清單是否一致。

---

## 九、紅線檢查

| 紅線 | 狀態 |
|---|---|
| `FoodPicker.swift` 零變更 | ✅ |
| 八條產品規則行為零變化 | ✅ 抽樣沒動。P2-3 改的是「名字存在哪」，不是「抽到誰」 |
| 既有 43 支不准為了讓它過而改 | ✅ 一個字沒改 |
| 每一項修正都要有先紅過的測試 | ✅ 五項都有 |

---

## 十、Commit 計畫（等你驗過）

```
FoodRotate/Models/SpinRecord.swift                （改：source + winnerID + 降級）
FoodRotate/Views/HistoryView.swift                （改：能還原的才是按鈕）
FoodRotate/Views/RotateView.swift                 （改：存 source/winner、winnerID 傳下去）
FoodRotate/Views/FoodCardList.swift               （改：winnerName → winnerID）
FoodRotate/Views/FoodEditorView.swift             （改：拿掉會製造孤兒覆寫的 rename）
FoodRotate/Services/CustomFoodStore.swift         （改：自訂料理單一名稱來源、defaults 可注入）
FoodRotate/Services/NearbySearch.swift            （改：距離文案）
FoodRotate/Views/NearbyRestaurantsView.swift      （改：地圖視窗）
FoodRotateTests/SpinRecordTests.swift             （新：8 支）
FoodRotateTests/SearchRadiusCopyTests.swift       （新：2 支）
FoodRotateTests/CustomFoodStoreRenameTests.swift  （新：6 支）
FoodRotateTests/NearbyMapCameraTests.swift        （新：3 支）
```

工作區開工前是乾淨的、與 `origin/main` 同步（我確認過，沒有分岔）。
