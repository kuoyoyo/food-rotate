# 工程回覆 — S1b 完工報告（給 PM）

**日期**：2026-08-11 ／ **提出**：程式設計師
**依據**：`PM裁示-S1開工前提問-回覆.md`（問題一選項 B、問題二全做、問題三 PDF 向量）
**基準點**：`6b2a37f`
**狀態**：**已完工，未 commit，等 PM 同意**

---

## 一、做了什麼

| # | 項目 | 檔案 | 說明 |
|---|---|---|---|
| 1 | token 單一來源 | `FoodRotate/DesignTokens.swift`（新增） | 只依賴 Foundation，App 與 icon 腳本共用同一份 |
| 2 | 薄設計系統 | `FoodRotate/Theme.swift`（新增） | 把 token 包成 SwiftUI 型別，不做元件 |
| 3 | 轉盤換 B 案色 | `FoodRotate/Views/WheelView.swift` | 拿掉硬寫的 8 色，改讀 token，淺深兩套 |
| 4 | icon 腳本同源 | `Tools/make-icon.swift` | 改讀同一份 token，過時註解已修 |
| 5 | 資料檢查 | `FoodRotate/Core/FoodDataAudit.swift`（新增）、`FoodLibrary.swift` | DEBUG 期檢查標籤覆蓋率與 id 撞號 |
| 6 | 測試 | `FoodRotateTests/`（新增）、`project.pbxproj`、`FoodRotate.xcscheme` | test target + 8 個測試 |

### 單一來源是怎麼做到的

`DesignTokens.swift` **刻意只 import Foundation**，因為它有兩個消費者：App 端的
`Theme.swift`（包成 `Color`）與 `Tools/make-icon.swift`（包成 `CGColor` 再加深）。
值只有一份，兩邊各自決定怎麼詮釋。

連帶的一個改動：**icon 腳本的跑法變了**，因為它現在要跟 token 一起編。

```
# 舊
swift Tools/make-icon.swift <輸出路徑>

# 新
swiftc Tools/make-icon.swift FoodRotate/DesignTokens.swift -o /tmp/make-icon \
    && /tmp/make-icon <輸出路徑>
```

多檔編譯時頂層程式碼必須放 `main.swift`，為了留住 `make-icon.swift` 這個檔名，
進入點改用 `@main` 包起來。**畫圖的邏輯一行都沒動**，diff 看起來大是因為整段縮排進了
`static func main()`。

---

## 二、留空的清單（等 S1a `設計規格-Theme-v1`）

照裁示條件 1、2，這些**一個都沒有填暫定值**，用到就是編不過或直接報錯：

| 未定案項目 | 現況 |
|---|---|
| 字級階層 | `Theme` 沒有對應 API |
| 間距階層 | 同上 |
| 髮絲線的顏色與透明度 | 只有 `hairlineWidth`，沒有 `hairlineColor` |
| 深色模式的頁面底／卡片／文字 | `Theme.Light` 存在，**刻意沒有 `Theme.Dark`** |
| icon 加深公式 | `make-icon.swift` 跑起來會停，訊息說明缺什麼、去哪要 |

`make-icon.swift` 目前執行的輸出：

```
Fatal error: icon 版的加深規則還沒有定案，這支暫時不能跑。
缺的是「從 DesignTokens 的轉盤八色推導出 icon 用深色」的公式，
要等設計師交 `設計規格-Theme-v1`（S1a）。規格到位後把這個函式實作掉即可，畫圖的部分都還在。
```

**這代表 App Icon 在 S1a 之前不能重產。** 現有的 `AppIcon.png` 沒有動，App 照常有 icon，
只是它是舊色盤畫的 —— 等規格到位重跑一次就會跟上。

另外圓角的 10 / 8 我只照大小命名（`radiusLarge` / `radiusSmall`），**沒有自己決定
哪個元件用哪一個**，那要等規格。

---

## 三、驗證

| 項目 | 結果 |
|---|---|
| `FoodRotate` App 建置 | ✅ BUILD SUCCEEDED |
| `FoodRotateWidgetExtension` 建置 | ✅ BUILD SUCCEEDED（確認沒被波及） |
| 單元測試 | ✅ 8 個全過（`TEST SUCCEEDED`） |
| `make-icon.swift` 編譯 | ✅ 編得過，執行時如上明確報錯 |
| 資料檢查跑真實 `foods.json` | ✅ 抓到 7 個問題，見第四節 |

### 八條產品規則

**行為零變化。** 這輪動到的是顏色來源、一支離線腳本、一個 DEBUG 期的印訊息，
以及新增的測試 —— `FoodPicker`、`FilterBar`、`FoodEditorView` 的邏輯**一行都沒改**。
新增的測試正是拿來釘住第 1、2 條的。

### 測試內容（`FoodRotateTests/FoodPickerTests.swift`）

PM 指定的兩條，加上三條順手釘住的相鄰行為：

1. 忌口篩完為空 → `isOverConstrained`，且 `relaxedDimensions` 為空（**沒進放寬迴圈**）
2. 忌口有得選時，放寬過程中也不會混進不符合忌口的菜
3. 「日式 + 無牛」5 道湊 6 格 → 5 道日式全在結果裡，第 6 格才是別的菜系，且回報放寬了菜系
4. 多層放寬時逐層累積、不重複收同一道菜，且放寬順序是**先吃法後菜系**（由後往前）
5. 上一輪的菜是「排後面」不是「排除」，候選池剛好時仍湊得滿

測試**不用 `FoodLibrary.all`**，改用自己造的候選池：真實資料會隨加菜改變，
用它當測試基礎的話，哪天紅了會分不出是規則壞了還是資料變了。
會受洗牌影響的斷言各跑 50 次，避免一次僥倖通過。

---

## 四、發現的問題（需要 PM／設計師決定，我沒有動）

### 1. 內建資料有 7 道菜缺圖示要用的標籤 —— **會擋住 S2**

這正是 PM 要求補這道檢查的理由，第一次跑就中了：

```
⚠️ foods.json 資料檢查：7 個問題
  • 美式烤肋排（bbq-ribs）少了「吃法」維度的標籤
  • 美式牛排（steak）少了「吃法」維度的標籤
  • 法式燉牛肉（boeuf-bourguignon）少了「吃法」維度的標籤
  • 夏威夷生魚飯（poke-bowl）少了「菜系」維度的標籤
  • 低卡餐盒（low-calorie-bento）少了「菜系」維度的標籤
  • 麻辣火鍋（mala-hotpot）少了「菜系」維度的標籤
  • 清燉羊肉爐（lamb-hotpot）少了「菜系」維度的標籤
```

圖示是「菜系 × 形態」推出來的，這 7 道現在推不出圖示名。**補什麼標籤是內容決策**
（麻辣火鍋算不算中式？牛排的「吃法」是什麼？），不是我該自己填的，所以我只讓它出聲。

順帶一提，這也不只是圖示問題：缺菜系標籤的那 4 道，**現在就已經**選了任何菜系都篩不到。

### 2. 提案的「12 菜系 × 6 形態」跟程式對不上

`FoodTag` 實際是 **10 個菜系 × 7 個吃法**（菜系少 2、吃法多 1，而且叫「吃法」不叫「形態」）。
設計師畫圖示前需要正確的數字，否則會多畫 2 張沒人用、少畫 1 張要用的。

實際的清單：

- 菜系（10）：台式・中式・日式・韓式・東南亞・南亞・義式・美式・歐陸・墨西哥
- 吃法（7）：麵食・飯食・湯的・鍋物・小吃・麵包餅皮・輕食

而且**一道菜可以同時有多個吃法**（現有資料裡有 11 道，例如牛肉麵是「麵食 + 湯的」、
韓式泡菜豆腐鍋是「鍋物 + 湯的」）。組合圖示要決定這種情況取哪一個 —— 這也是設計師的題。

### 3. `category` 欄位混了非菜系的值

`foods.json` 的 `category` 出現「輕食」「鍋物」這種**吃法**的值，跟其他 10 個菜系值混在一起。
上面第 1 點那 4 道缺菜系標籤的，剛好就是 `category` 放了吃法的那幾道。
`FoodLibrary.categories` 會把它們一起列出來。這是既有狀況，**我沒有動**。

---

## 五、看到但沒有順手改的（依工作約定寫進報告）

| 東西 | 為什麼沒動 |
|---|---|
| `WheelView.shortened()` 5 字截斷 | 這就是 S2 要解的 P0，現在改等於提前動主戰場 |
| 12 格時色盤會繞回來重複用色 | 8 色配 10／12 格必然重複。相鄰格沒有撞色，但同一盤上會看到兩塊同色，S2 或設計師的題 |
| Widget target 拿不到 token | `DesignTokens.swift` 在 App 的同步資料夾裡，Widget 要用得搬去 `Shared/`（那會動到 pbxproj）。目前 Widget 沒有用到色票，等它需要再說 |
| `SpinRecord.engineRawValue`、店家借用 `FoodItem` | 交接文件列為刻意保留的技術債 |

---

## 六、Commit 計畫（**等 PM 同意才執行**）

依裁示分兩筆，pbxproj 自成一筆。第二筆依賴第一筆，順序不能反。

### 第一筆：設計系統與資料檢查

```
FoodRotate/DesignTokens.swift      （新增）
FoodRotate/Theme.swift             （新增）
FoodRotate/Core/FoodDataAudit.swift（新增）
FoodRotate/Core/FoodLibrary.swift  （改：DEBUG 期跑檢查）
FoodRotate/Views/WheelView.swift   （改：色盤改讀 token）
Tools/make-icon.swift              （改：同源 + 加深待補 + 修註解）
```

訊息草稿：

```
S1b：收攏設計 token，轉盤換 B 案色盤

轉盤八色與 icon 腳本改讀同一份 DesignTokens，不再各寫一份。
字級／間距／髮絲線顏色／深色底色／icon 加深公式等 S1a 規格，
刻意留空不填暫定值：用到就編不過，icon 腳本則直接報錯。

順帶補上 foods.json 的 DEBUG 期檢查（缺菜系／吃法標籤、id 撞號），
只印不當掉——缺標籤是內容問題，不該讓 App 開不起來。
```

### 第二筆：測試

```
FoodRotate.xcodeproj/project.pbxproj                      （改：新增 test target）
FoodRotate.xcodeproj/xcshareddata/xcschemes/FoodRotate.xcscheme（改：補 test action）
FoodRotateTests/FoodPickerTests.swift                     （新增）
FoodRotateTests/FoodDataAuditTests.swift                  （新增）
```

訊息草稿：

```
S1b：加上 test target 與 FoodPicker 的行為測試

釘住兩條實跑抓過 bug 的規則：忌口永不放寬、放寬是往下補不是重來。
在基準點附近寫，之後 S2 改 WheelView、S4 改 FilterBar 才有東西接得住。

scheme 原本沒有 test action，一併補上，否則命令列跑不了測試。
```

**`Design/` 與四份 .md 文件仍未追蹤**，要不要一起進、進哪一筆，請 PM 指示。

---

## 七、我現在的狀態

S1b 做完了，停在 commit 之前。被擋住的是需要 S1a 規格的那幾個值，以及第四節第 1、2 點
要設計師回答的資料問題 —— 第 1 點**在 S2 開工前必須有答案**，否則有 7 道菜沒有圖。
