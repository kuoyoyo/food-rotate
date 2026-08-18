# 工程回覆 — S6 收尾的兩件小事

**日期**：2026-08-18 ／ **提出**：程式設計師
**依據**：`Coder/PM驗收-S6第三批-通過.md` 末節（`save` 註解、`DishListRow` 警告）
**狀態**：兩件都做完，**未 commit**。P1-5 依然沒有動。

---

## 一、`HistoryStorage.save(_:)` 補上「為什麼沒有整合測試」

照你說的，決定跟程式碼放在一起。寫進去的三條理由：

- 要驗的是**錯誤有沒有被吞掉**，而那已經收斂在這一個方法裡，兩條分支都被 `recordSave(error:)` 走過
- 「SwiftData 在磁碟滿的時候會不會 throw」是在測 Apple
- 那條路唯一的後果是「提示沒跳出來」，狀態機有測試背書

**多寫了一句你沒說的**，因為我覺得少了它這段註解會誤導下一個人：

> 反過來說，要是有人把 `do/catch` 拆回各個呼叫點，上面那個論證就不成立了 ——
> 收斂到一個入口正是它能夠只靠單元測試的前提。

不然這段讀起來會像「這裡不用測」的通行證，但它其實是**有條件的**：條件就是唯一入口。

---

## 二、`DishListRow.swift:109` 的警告

### 警告原文（重現過才動手）

```
FoodRotate/Views/DishListRow.swift:109:40: warning:
main actor-isolated static property 'separatorInset'
can not be referenced from a Sendable closure
```

一開始的增量 build 沒有噴 —— 那個檔沒有被重編。`touch` 之後才出現。
**沒有重現就不算修過**，所以先讓它出來。

### 成因

`View` 是 `@MainActor`，型別裡的 static 屬性跟著繼承那個隔離。
而 `alignmentGuide` 的 closure 是 `@Sendable`（版面計算不保證在主執行緒）。

### 改法

真正的答案不是把 closure 想辦法搬回主執行緒，是**這兩個常數本來就不需要主執行緒** ——
它們是純幾何數字（32、12+32+12），跟畫面狀態無關。兩個都加 `nonisolated`。

保持 computed 而不是改成 `static let`：泛型型別不能有 static 儲存屬性。這一點也寫進註解了，
免得下一個人以為是隨手寫成 `var`。

### 我沒有順手做的

`DishListRow<EmptyView>.separatorInset` 這個寫法還是彆扭 —— 為了讀一個常數要隨便填一個泛型參數。
搬進一個 `nonisolated enum DishListRowMetrics` 會乾淨，但那是**改結構不是清警告**，
不在你交辦的範圍裡。**記著，沒做。**

---

## 三、驗證

| 項目 | 結果 |
|---|---|
| clean build 全專案警告 | ✅ **0**（唯一剩下的是 `appintentsmetadataprocessor` 那行，來自工具鏈不是我們的程式） |
| 測試 | ✅ **80 支 / 16 suites 全過**，5.480 秒 |
| 行為 | 兩處都是註解與隔離標註，**零行為變更**。分隔線縮排的值一模一樣（12+32+12） |

我沒有再截一次圖：這一批沒有任何一行會改變畫面上的像素。

---

## 四、變更清單（等你點頭）

```
FoodRotate/Services/HistoryStorage.swift   （改：save 補決定註解，純註解）
FoodRotate/Views/DishListRow.swift         （改：兩個 static 加 nonisolated + 說明註解）
```

建議訊息：`S6 收尾：把「不做整合測試」的理由寫進程式碼，清掉 DishListRow 的隔離警告`

---

## 五、你記進待辦的另一件，我沒有動

**歷史頁空的時候不顯示降級提示** —— 提示確實在 `records.isEmpty` 的 `else` 分支裡。
你判斷「空清單時沒有東西會失去，所以不新增損失視窗」，我同意那個取捨，
所以**不順手改**。要改的時候再說一聲。
