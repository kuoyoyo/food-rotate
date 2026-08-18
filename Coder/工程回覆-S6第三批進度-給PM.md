# 工程回覆 — S6 第三批進度（P2-5 完成、P3-1 部分）

**日期**：2026-08-17 ／ **提出**：程式設計師
**依據**：`Coder/PM派工-S6-工程.md` 第三節
**狀態**：**P2-5 做完。P3-1 推進一段但沒有做完。未 commit。**
P1-5 依你指示**沒有動**。

---

## 一、P2-5 降級不再靜默

### 原本有兩層都在無聲失敗

1. `ModelContainer` 建不起來 → 退回記憶體，`catch` 裡什麼都沒做
2. 每一次寫入 → `try? context.save()`，錯誤直接吞掉

加起來的結果是**使用者以為存了，重啟發現不見了**。
降級本身要保留（歷史壞掉不該讓 App 開不起來），要改的是不講。

### 做法

新增 `Services/HistoryStorage.swift`：

| 狀態 | 語意 |
|---|---|
| `isEphemeral` | 這次啟動退回了記憶體。**整個 session 的事實** —— 之後寫入成功也不會清掉它，因為「寫得進記憶體」不代表「存得住」 |
| `lastSaveFailed` | 最近一次寫入失敗。**下一次成功就收掉** —— 一個一直亮著的警告等於沒有警告 |

`try?` 從三個呼叫點**收斂到一個地方**（`HistoryStorage.save(_:)`），
這樣「錯誤被吞掉」不可能再重新長出來。失敗一律進 `Logger`（category: `history`）。

### 提示文字講後果，不講原因

> 歷史暫時沒辦法保存，這次轉出的紀錄關掉 App 就會消失。其他功能都正常。

「SwiftData container 初始化失敗」對使用者沒有意義；「關掉就會消失」他可以據此決定要不要現在截圖。
最後那句「其他功能都正常」是刻意的 —— 不要讓一個局部故障看起來像整個 App 壞了。

放在**歷史頁**而不是全 App：提示要出現在使用者會受影響的地方，不是最顯眼的地方。
非阻擋、正常時完全不佔位。

### ✅ 實機（`S6-degraded.png`）

那張截圖一次驗到兩件事：

1. **降級提示**：單行、次要色、不擋操作、清單完整沒被推掉
2. **餐廳紀錄那一列** —— 你上午轉的「大師兄銷魂麵舖」還在模擬器裡，
   所以我**看到了**：沒有還原符號、沒有菜系角標、其餘樣式與其他列完全相同。
   **我原本標成「未實測」的三項，這一項可以改成已驗證了。**

---

## 二、⚠️ 這一組測試我沒有先看到紅，補了拆開驗

`HistoryStorage` 是新型別 —— 缺陷是「**什麼都沒有**」，所以沒有舊實作可以讓測試紅。
我不想含糊帶過，所以做了拆開驗：把 `notice` 改成永遠 nil、`isDegraded` 改成永遠 false
（也就是 S6 之前的靜默行為），跑起來 **8 個 issue**。restore 之後全綠。

**這組測試有牙，但它的紅是我自己造出來的，不是既有缺陷本身的紅。** 兩者不一樣，記在這裡。

---

## 三、P3-1 的進度（沒做完）

你說這批是「補齊不是從零」。目前的實際位置：

| QC 的順序 | 狀態 |
|---|---|
| 1. 抽成可注入的小介面 | **六個注入點都在**：`WheelSpinner.Wait`、`RotateViewModel(spinner:)`／`(nearby:)`、`NearbySearchModel.TermQuery`／`LocationProvider`、`CustomFoodStore(defaults:)` |
| 2. 狀態機單元測試 | ✅ 取消、過期 callback、快速切模式、重複搜尋、reset/spin race 都有 |
| 3. 整合測試 | 🟡 **UserDefaults 重啟一致**這次補了 2 支（建第二個 store 讀同一個網域 = 重新開 App）。**餐廳歷史保存／SwiftData save failure 還沒有** |
| 4. UI tests | ❌ **一支都沒有** |

43 → 80（+37）。既有 43 支從 S6 開始一個字沒改。

### 剩下兩塊我要先講清楚範圍

**SwiftData save failure 的整合測試**：要讓 `context.save()` 真的失敗才測得到
（唯讀容器、磁碟滿、schema 衝突），這幾個在測試環境不好穩定製造。
我可以測 `HistoryStorage.recordSave(error:)` 的狀態機（已經有了），
但「真的存不進去」那條路我目前只能靠注入假錯誤 —— **那不算整合測試，別讓表格看起來比實際好。**

**UI tests**：這是唯一能自動驗「觸控之後畫面對不對」的東西，
也正好補上我從 S2 一路標「未實測」的那一整類。但它是新的 target、新的 scheme 設定，
會動 pbxproj。**要不要現在開，以及要不要為此改 pbxproj，我等你裁示。**

---

## 四、實機回歸：我能做的與不能做的

你列的九項裡：

| 項目 | 我能不能 |
|---|---|
| 深淺模式、reduce motion | ✅ 做過（S5 逐頁 + reduceMotion 實測） |
| 無搜尋結果、fallback、定位拒絕、定位逾時 | ⚠️ 需要製造特定環境（關定位、斷網、選一個沒有店的菜系）——**其中「關定位」我改不了模擬器的權限對話框** |
| 快速換條件、切模式 | ❌ 需要連續點按 |
| 餐廳歷史 | ✅ 剛好驗到（見第一節） |
| 地圖視窗框住遠處的店 | ❌ 需要一家 8 公里外的店 |

**這一段的驗證重量在你手上，不在我手上。** 我能給的是：那些行為都有測試背書，
而測試背書的是邏輯，不是觸控之後的畫面。

---

## 五、Commit 計畫（等你驗過）

```
FoodRotate/Services/HistoryStorage.swift              （新：降級狀態 + 唯一寫入點 + Logger）
FoodRotate/FoodRotateApp.swift                        （改：container 走 HistoryStorage）
FoodRotate/Views/HistoryView.swift                    （改：非阻擋提示、寫入走同一個入口）
FoodRotate/Views/RotateView.swift                     （改：寫入走同一個入口）
FoodRotateTests/HistoryStorageTests.swift             （新：5 支）
FoodRotateTests/CustomFoodStoreRenameTests.swift      （改：+2 支重啟一致）
```

---

## 六、要你裁示的兩件

1. **UI test target 要不要開？** 會動 pbxproj。開了才有辦法自動驗觸控後的畫面 ——
   那是我從 S2 到現在唯一沒有辦法自證的一整類。
2. **SwiftData save failure 的整合測試值不值得做？** 要穩定製造真實失敗，
   成本比它擋下的風險高（那條路唯一的後果是「提示沒跳出來」，而狀態機已經有測試）。
   我傾向不做，但寫在這裡讓你決定，不自己吞掉。
