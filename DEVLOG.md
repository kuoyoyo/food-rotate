# 食物轉盤 開發紀錄

**專案**：FoodRotate（食物轉盤）
**設計**：kuoyo　**製作**：Claude Code
**開始日期**：2026-08-05

這份文件記錄製作過程的重大決策、遇到的問題與解法。依時間順序往下加。

> **讀之前先知道一件事**：前半段記錄的是**已經被拿掉的語言模型架構**。
> 2026-08-11 改成內建資料庫 + 標籤篩選（見 [`大改紀錄-拿掉語言模型.md`](大改紀錄-拿掉語言模型.md)）。
> 那段沒有刪掉，因為「為什麼放棄」跟「後來做了什麼」一樣重要。
> 想知道專案現在長什麼樣，看 [`PROJECT_STATUS.md`](PROJECT_STATUS.md)。

---

## 一、需求確認

kuoyo 的原始需求：

- 原生 iOS App，**不做網頁端**
- 使用者輸入「想吃什麼」或食物類型
- 語言模型自動產生食物清單放進轉盤
- 顯示食物列表，並解釋每種料理的優缺點
- 版權標示：Claude Code 製作、kuoyo 設計

追問後確認的四個決策：

| 項目 | 決定 |
|---|---|
| 模型來源 | Apple 裝置內建模型 **與** 自架 OpenAI 相容模型，兩者都要 |
| 引擎切換 | 設定頁手動選主引擎，主引擎失敗自動 fallback，UI 標示實際使用的引擎 |
| 功能範圍 | 核心轉盤 + 歷史紀錄 + 附近餐廳 |
| 發布方式 | 先在 iPhone 17 Pro 模擬器跑起來 |

## 二、環境勘查

開工前先確認手上有什麼，避免規劃出跑不動的東西。

| 項目 | 結果 |
|---|---|
| Xcode | 26.6（Build 17F113） |
| iOS SDK | 26.5 |
| Mac | Apple M4 / macOS 26.5.2 |
| `FoundationModels.framework` | 在 iPhoneOS SDK 內，可用 |
| Swift | 6.3.3 |
| xcodegen / tuist | 都沒有 |
| 本機 LLM server | 沒有在跑（`ollama` 有裝但未啟動） |

順手掃了常見的 LLM port（11434 / 1234 / 8080 / 8000 / 5000 / 3000）。port 5000 回 403，一度看起來像有服務，實際上是 macOS 的 AirPlay Receiver，不是 LLM。這點記下來，之後測連線不要被它誤導。

## 三、重大決策

### 決策 1：不手刻傳統 pbxproj，改用 Xcode 26 的檔案系統同步群組

**問題**：沒有 xcodegen 或 tuist，專案檔得自己生。傳統 `project.pbxproj` 每個原始檔都要一組 `PBXBuildFile` + `PBXFileReference` 條目，二十幾個檔案手寫下來極易出錯，之後每加一個檔案還要再改一次。

**解法**：改用 `objectVersion = 77` 搭配 `PBXFileSystemSynchronizedRootGroup`。這個群組型別讓專案自動同步整個 `FoodRotate/` 資料夾，新增 Swift 檔案完全不用動專案檔。

**代價**：`Info.plist` 不能放在同步資料夾內，否則會同時被當成資源檔複製進 bundle。因此 `Info.plist` 放在專案根目錄，用 `INFOPLIST_FILE` 指過去。

### 決策 2：先讀 SDK 的 `.swiftinterface` 再寫程式

**問題**：`FoundationModels` 是很新的框架，`@Guide` 的參數形狀、`availability` 的 enum case、`respond(to:generating:)` 的簽名如果記錯，會浪費好幾輪 build 失敗。

**解法**：直接讀 SDK 內的
`FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface`
把要用的 API 全部確認過再動筆。確認到的關鍵事實：

- `GenerationGuide.count(_:)` 有 `Int` 與 `ClosedRange<Int>` 兩種版本，所以 `.count(2...3)` 合法
- `SystemLanguageModel.Availability.UnavailableReason` 有 `deviceNotEligible`、`appleIntelligenceNotEnabled`、`modelNotReady` 三個 case
- `LanguageModelSession.GenerationError` 有 `guardrailViolation`、`refusal`、`rateLimited` 等九個 case，可以分類給出不同的中文說明
- `respond(to:generating:)` 回傳的 `Response<Content>` 用 `.content` 取值

同樣的手法也用在 CoreLocation 上，確認 `CLServiceSession(authorization:)` 與
`CLLocationUpdate.liveUpdates()` 都存在且是 `Sendable`。

### 決策 3：關掉 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

**問題**：一開始照 Xcode 26 新專案的預設，把預設 actor 隔離設成 `MainActor`。但這會讓 `struct FoodItem` 也變成 MainActor 隔離，而 `@Generable` 巨集產生的 `Generable` conformance 需要 nonisolated，兩者會打架。

**解法**：拿掉這個設定，回到預設的 `nonisolated`，改成在需要的型別上明確標 `@MainActor`（引擎、設定、view model），資料模型維持 nonisolated + `Sendable`。`SWIFT_APPROACHABLE_CONCURRENCY = YES` 保留，它帶來的 `nonisolated(nonsending)` 對 async 函式很有幫助。

### 決策 4：自架模型不使用 `response_format: json_schema`

**問題**：OpenAI 官方 API 支援 structured output，但 Ollama、LM Studio、llama.cpp、vLLM 的相容層對它的支援程度差很多，有的直接回 400。寫死這個參數會讓「自架」這個賣點在一半的後端上直接掛掉。

**解法**：把 JSON schema 寫進 system prompt，回應端做容錯解析。解析器要處理三種實際會遇到的髒資料：

1. 包在 ` ```json ` fence 裡
2. 前後多一段中文說明文字
3. 推理模型先吐一段 `<think>…</think>` 才給答案
4. 直接回一個沒有 `items` 外層的陣列

`OpenAICompatEngine.parseItems(from:)` 四種都接住。

### 決策 5：轉盤不用 `withAnimation`，自己算角度

**問題**：轉盤要在「每跨過一格」的瞬間給觸覺回饋，模擬實體轉盤打到卡榫的手感。但 SwiftUI 的 `withAnimation` 是黑箱，動畫進行中無法得知目前轉到哪個角度。

**解法**：自己定義三次緩出函數 `e(x) = 1 - (1-x)³`，角度由 `TimelineView` 的時間戳算出來（純函數，放在 view body 裡安全）。觸覺的時間點則用緩出函數的**反函數** `e⁻¹(y) = 1 - (1-y)^(1/3)`，在起轉前一次算完所有跨格的秒數，再用一個 Task 依序睡到每個時間點。

這樣做的好處：不會漏拍、不在 view body 裡做副作用、緩出的手感自己完全掌控。

**先決定贏家再回推角度**：指針固定在 12 點鐘，轉盤順時針轉 θ 度後，指針下方是本地角度 `(-θ mod 360)`。要讓第 w 格停在指針下，θ 必須同餘於 `360 - (w + 0.5) × 每格角度`。這個順序很重要，反過來「先轉再看停在哪」會因為浮點誤差選錯格。

### 決策 6：定位走 iOS 18 之後的 async API，不用 delegate

**問題**：`CLLocationManagerDelegate` 是 15 年前的 callback 介面，在 Swift 6 嚴格併發下要靠 `MainActor.assumeIsolated` 手動橋接，容易出錯。

**解法**：改用 `CLServiceSession(authorization: .whenInUse)` 觸發授權，`CLLocationUpdate.liveUpdates()` 取位置。整條路徑都是 async/await，沒有資料競爭問題。

**要注意的兩個坑**（都已處理）：

1. `liveUpdates()` 是**無限序列**，拿到第一個有效位置就要主動 break，否則會一直跑
2. 授權對話框開著的時候不會有任何 update 進來，所以另外開一個 30 秒逾時的 task 跟它賽跑

### 決策 7：轉盤幾何抽成獨立的純函數檔

**問題**：轉盤最怕的錯誤是「先決定贏家，轉完卻停在別格」。這段邏輯原本寫在 `WheelSpinner`
裡面，而 `WheelSpinner` 依賴 SwiftUI 與 UIKit，在 macOS 上編不起來，等於測不到。

**解法**：把角度計算抽成 `Models/WheelGeometry.swift`，不依賴任何 UI 框架。
`WheelSpinner` 只負責動畫狀態與排程，計算全部委派出去。這樣可以用 macOS 直接編譯真正的
那份程式碼做窮舉測試，不必複製一份會走鐘的副本。

## 四、專案結構

```
food rotate/
├── DEVLOG.md                 這份文件
├── Info.plist                放在同步資料夾外（見決策 1）
├── FoodRotate.xcodeproj/
└── FoodRotate/
    ├── FoodRotateApp.swift
    ├── Assets.xcassets/
    ├── Models/      FoodItem, SpinRecord, AppSettings
    ├── Engines/     FoodSuggesting, AppleEngine, OpenAICompatEngine, EngineRouter
    ├── Services/    KeychainStore, NearbySearch, Haptics
    └── Views/       Root, Wheel, PromptBar, FoodCardList, ResultSheet, History, Nearby, Settings
```

`Info.plist` 需要的三個 key：

- `CFBundleDisplayName` — 顯示為「食物轉盤」
- `NSLocationWhenInUseUsageDescription` — 附近餐廳需要
- `NSAppTransportSecurity` → `NSAllowsLocalNetworking` — 自架模型多半是 `http://` 區網位址，不開這個會被 ATS 擋掉

API key 存 Keychain 而非 UserDefaults，因為 UserDefaults 會被備份到 iCloud 與 iTunes，不適合放憑證。

## 五、驗證方式與遇到的阻礙

### 阻礙：無法用指令碼點按模擬器

模擬器面板的裝置存取權限沒有被授予，`osascript` 驅動 Simulator 視窗會卡在
Accessibility 權限對話框，`idb` 也沒安裝。結論是**沒有任何方式可以用指令碼點按畫面**。

繞過的方式有兩層：

1. **純邏輯直接在 macOS 上編譯執行**。`FoodItem`、`AppSettings`、`KeychainStore`、
   `FoodSuggesting`、`OpenAICompatEngine`、`WheelGeometry` 這些檔案不依賴 UIKit，
   可以用 `swiftc -target arm64-apple-macos26.0` 直接編譯真正的原始檔來測，
   不是複製一份會走鐘的副本。
2. **`#if DEBUG` 的啟動參數後門**。`NSUserDefaults` 會自動讀取 `-key value` 形式的
   命令列參數，所以不用寫任何解析程式就能從 `xcrun simctl launch` 注入狀態。
   四個參數：`-demoMenu`、`-autoSpin`、`-autoGenerate <需求>`、`-startTab <分頁>`。
   全部包在 `#if DEBUG`，已用 `strings` 確認 Release binary 裡一個都找不到。

用法：

```bash
xcrun simctl launch <UDID> com.kuoyo.foodrotate -demoMenu YES -hasSeenWelcome YES -autoSpin YES
```

### 驗證結果

| 項目 | 方式 | 結果 |
|---|---|---|
| Debug build | `xcodebuild` | 通過，零錯誤零警告 |
| Release build | `xcodebuild -configuration Release` | 通過，零錯誤零警告 |
| Debug 後門未進 Release | `strings` 掃描 Release binary | 0 個符合，確認乾淨 |
| 髒 JSON 容錯解析 | macOS 直接編譯真實原始檔 | 14 項全過 |
| 自架模型網路路徑 | Python mock server（3 個 port 模擬正常／401／500） | 8 項全過 |
| 轉盤落點正確性 | 窮舉 25760 種組合 | 全部停在指定格 |
| 觸覺排程 | 檢查次數、遞增、範圍、強度遞減 | 通過，44 次卡榫 |
| 轉盤／結果頁／設定頁／歷史頁 | 模擬器截圖 | 通過 |
| 歷史跨啟動持久化 | 轉兩次後重啟看歷史頁 | 兩筆都在，內容正確 |
| 引擎自動 fallback | 主引擎設裝置模型（會失敗）＋ mock server | 通過，正確切換並說明原因 |

窮舉測試涵蓋 2/3/5/6/8/10/12 格 × 每一格 × 20 種起始角度 × 7 種格內偏移 × 4 種圈數。

## 六、實測抓到的問題

以下五個都是實際跑起來才發現的，寫程式當下都看不出來。

### 問題 1：模擬器謊報裝置模型可用

**現象**：設定頁顯示「裝置內建模型：可以使用」，但實際產生時直接失敗。

**原因**：這台 Mac 的 macOS Apple Intelligence 是關閉的（用 `SystemLanguageModel.default.availability`
在 macOS 上直接查，回 `appleIntelligenceNotEnabled`）。但 iOS 26.5 模擬器的
`availability` 卻回報 `.available`。**模擬器的可用性回報不可信**，只有真的送出請求才知道。

**影響**：不能只靠 `availability()` 判斷，`suggest()` 的錯誤處理必須夠強壯。
自動 fallback 從「好用的功能」變成「必要的功能」。

### 問題 2：裝置模型拋出的錯誤轉型不成 `GenerationError`

**現象**：畫面顯示「無法完成作業。(FoundationModels.LanguageModelSession.GenerationError 錯誤-1。)」
這種對使用者毫無幫助的原始字串。

**原因**：程式原本寫 `catch let error as LanguageModelSession.GenerationError`，
但模擬器實際拋出的是 domain 為該型別名稱、code 為 -1 的橋接 NSError，型別轉換不成立，
所以整段翻譯邏輯被跳過。

**修正**：`AppleEngine.suggest` 加一個涵蓋所有錯誤的 `catch`，把無法辨識的錯誤一律換成
講清楚原因與下一步的中文說明。這條路徑截圖驗證過。

### 問題 3：轉盤左半邊的字上下顛倒

**現象**：右半邊的「牛肉麵」「鹽酥雞」讀得很順，左半邊的「關東煮」「泡麵加蛋」整個倒過來。

**原因**：字沿著扇形中線畫，中線角度落在 90°–270°（畫面左半邊）時，文字方向自然朝左，
看起來就是顛倒的。這是徑向文字的典型問題。

**修正**：左半邊多轉 180°，並把繪製點鏡射到 -x。位置完全不變，字面轉正。

### 問題 4：版權年份被當成數字格式化

**現象**：版權標示顯示「© 2,026 kuoyo」，多了一個千分位逗號。

**原因**：`Text("© \(year) kuoyo")` 會把 `Int` 當成數字用地區設定格式化。

**修正**：改用 `Text(verbatim:)`。

### 問題 5：空轉盤時中心鈕與提示文字疊在一起

**現象**：還沒產生清單時，「轉」按鈕和「先在上面說想吃什麼」的提示重疊成一團。

**修正**：`items` 為空時不繪製中心鈕。

## 七、開啟 Apple Intelligence 之後的第二輪驗證

kuoyo 授予模擬器操作權限並開啟 Apple Intelligence 之後，補做了先前做不到的部分。

狀態變化可以直接觀察到：`SystemLanguageModel.default.availability` 從
`appleIntelligenceNotEnabled` 變成 `modelNotReady`（下載中），下載完成後裝置模型真的能用了。

### 補驗到的項目

| 項目 | 結果 |
|---|---|
| 裝置內建模型端對端 | 通過。用「宵夜」產生八道台式選擇，全繁體中文，完全離線 |
| 轉盤落點與結果一致 | 通過。轉出蚵仔煎後關掉結果頁，轉盤正停在蚵仔煎對準指針 |
| 設定頁「測試連線」 | 通過。回「連線成功，伺服器上有 gpt-oss:20b」 |
| 候選清單卡片展開 | 通過。優點綠色、缺點橘色，勝出項目有橘框與「轉中」標籤 |
| 產生中的載入狀態 | 通過。按鈕停用、轉盤遮罩、空轉盤不畫中心鈕 |

### 發現：裝置模型的繁中品質有明顯極限

第一輪產生的結果裡，蚵仔煎配到 🌽 玉米、分類成「輕食」，蝦仁炒飯被歸為「麵食」。
裝置端模型只有約三十億參數，自由生成分類與 emoji 的準確度不夠。

**修正**：用 `GenerationGuide.anyOf` 把 `category` 限縮成 16 個固定值。這個限制會直接寫進
`@Generable` 產生的 schema，模型選不出集合外的值。emoji 則在 `@Guide` 的描述裡給具體反例
（蚵仔煎用 🦪 不用 🌽）。自架模型沒有 schema 那層保護，所以同一份清單在 `PromptFactory`
裡再寫一次，兩邊產出的分類才會一致。

修正後重測，蚵仔煎正確拿到 🦪。

**仍然存在的限制**（屬於模型能力，不是程式問題）：小模型容易在同一個主題上打轉。
實測「宵夜，想吃重口味的」時出現豬血腸炒麵、豬血腸麵、豬血腸炒飯三道，八道去重後剩七道。
轉盤本身可以正常處理任意格數，七格照樣運作。想要更好的多樣性就切到自架的大模型。

### 發現：模擬器的硬體鍵盤走注音輸入法

用指令碼輸入 `127.0.0.1:8811` 會被注音輸入法轉成「ㄅㄉˋㄨㄢㄨㄢㄨㄅ:ㄚㄚㄅㄅ」。
這是模擬器的輸入法設定問題，不是 App 的 bug，真機上 `keyboardType(.URL)` 會給 URL 鍵盤。

意外的收穫是這驗證了位址驗證有效：欄位被塞進亂碼後，「測試連線」按鈕維持停用狀態，
因為 `normalizedBaseURL` 正確判定那不是合法位址。

## 八、GPS 與附近餐廳測試

用 `xcrun simctl location <UDID> set 25.0339,121.5645` 把模擬器定位設在台北信義區（台北 101 附近）。

### 通過的部分

定位授權、`CLLocationUpdate.liveUpdates()` 取位置、`MKLocalSearch` 搜尋、地圖標記、
距離排序、Apple 地圖導航入口全部正常。轉出滷肉飯時找到八家真實店家：
雞肉本家安和店 1.0 公里、滷肉飯便當 1.0 公里、帥哥滷肉飯 3.2 公里、金峰魯肉飯 4.6 公里…
距離由近到遠排序正確，地址與行政區都對。

### 問題 6：`MKLocalSearch` 找不到店家時是拋錯，不是回空陣列

**現象**：轉到「泡麵加蛋」時，畫面顯示「無法完成作業。(MKErrorDomain 錯誤 4。)」

**原因**：程式原本假設「找不到」會回一個空的 `mapItems`，所以只在
`places.isEmpty` 的時候給出「附近找不到賣 X 的店」。但 `MKLocalSearch.start()`
實際上是**丟出 `MKError.placemarkNotFound`（代碼 4）**，那段訊息根本沒有機會執行，
最後掉進通用的 catch 吐出原始字串。

**修正**：新增 `describeSearchFailure(_:dish:)`，把 `MKErrorDomain` 的六個代碼分別對應到
中文說明，非 MapKit 的錯誤原樣保留。

**驗證**：窮舉 `MKError` 全部六個代碼加上兩個邊界情況，8 項全過。

### 一個誤判：轉盤結果與附近搜尋不一致

一度看到結果頁顯示「麻辣鴨血」，附近搜尋的標題卻是「附近的關東煮」。

追下去發現是 `-autoSpin` 這個 debug 啟動參數被 `.task` 重複觸發，在截圖與點按之間
又轉了一次，換掉了 `model.winner`。改成純手動點按流程後標題正確顯示「附近的泡麵加蛋」。
**這不是 App 的 bug**，只是我的測試工具本身造成的假象。記在這裡是因為當下差點誤判成程式錯誤。

### 測試手法的新發現：iOS-only 程式碼也測得到

`NearbySearch.swift` 用到 `CLServiceSession`，這個型別在 macOS 上不存在，
所以先前那套「編成 macOS 執行檔直接跑」的手法對它無效。

解法是編成 iOS 模擬器的執行檔，再丟進模擬器裡跑：

```bash
swiftc -swift-version 6 -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) \
  -target arm64-apple-ios26.0-simulator Services/NearbySearch.swift main.swift -o test
xcrun simctl spawn <UDID> "$PWD/test"
```

這條路對任何 iOS 專屬的純邏輯都適用，不需要建立測試 target。
為了讓 `describeSearchFailure` 測得到，它維持 internal 而不是 private，
函數本身是純函數、沒有副作用，這個可見度是合理的取捨。

## 九、App Icon 與模型輸出品質

### App Icon

用 `Tools/make-icon.swift` 以 CoreGraphics 畫出 1024×1024 的 PNG，不是拉圖。
這樣八格配色能跟 `WheelView.palette` 對得起來，日後改了 App 內的轉盤顏色，重跑一次就同步。
檔案放在專案根目錄的 `Tools/`，不在 `FoodRotate/` 同步資料夾內，所以不會被編進 App。

```bash
swift Tools/make-icon.swift FoodRotate/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

第一版太淡，桌面上會糊掉。調整為：轉盤半徑從 0.355 放大到 0.390、中心圓縮小、
指針壓進輪框、背景漸層加深、八格顏色整體提高彩度。
App 內的轉盤有大片留白襯著，icon 在桌面上只有 60 點，粉彩會糊成一團灰。

### 問題 7：模型不遵守指定的料理類型

**現象**：輸入「想吃日式料理」，出來的是炸雞腿、牛腩麵、豬扒麵、蝦餃、麵包雞。
這些是港式茶餐廳的菜，八道裡只有兩道是日式。而且出現「蝦夾麵」這種不存在的菜名。

**原因**：`PromptFactory.role` 只說「熟悉台灣飲食環境的美食顧問」，
**沒有任何一條規則要求遵守使用者指定的料理類型**，也沒禁止自創菜名。

**修正**：規則第 1 條改成「使用者指定料理類型時，每一道都必須符合，一道都不能違反」，
第 2 條加上「只列出真實存在的菜名，不要把不同菜名的字拼在一起造新詞」。
`userPrompt` 也在結尾再問一次「這幾道是不是每一道都符合」，因為小模型生成到後面容易忘記前面的限制。

修正後八道全部日式，港式完全消失。

### 問題 8：模型把「多樣性」理解成換主食材

**現象**：料理類型修好之後，出現四個親子丼（鮭魚、雞肉、豬肉、豚肉）加三個炒飯。
轉盤變成「你的丼飯要哪種肉」。

**這個不能只靠 prompt**。同一段 prompt 跑兩次，一次給七種不同形式，一次給四個親子丼，
結果不穩定。所以加上程式層的確定性把關：

`FoodItem.dishForm` 從菜名的後綴判斷「料理形式」（親子丼、拉麵、刺身、定食…），
`normalized()` 限制同一種形式最多幾道。已知形式清單長的排前面，
這樣「親子丼」不會被「丼」先比中，「烏龍麵」也不會被「麵」吃掉。

### 問題 9：去重太狠，八格變三格

上面的限制寫死成「同形式最多 2 道」之後，遇到模型回一整批丼飯時，
十二道砍完只剩三道。三格的轉盤比八格裡有兩道相似的更難用。

**修正**：改成逐步放寬。先試 2 道，不足六格就放寬到 3 道、4 道，
真的還是不夠就只做同名去重。多樣性是偏好，湊滿格數是底線。

另外在 `EngineRouter` 加了補槍機制：第一輪去重後不足六道就再跑一輪合併。
最差多花一輪時間（裝置模型約 14 秒），仍在可接受範圍。

### 問題 10：優缺點都是套話

**現象**：缺點八道全寫「等待時間較長」，甚至同一道的兩則缺點是同一件事
（「可能需要排隊」＋「等待時間較長」）。優點則是「魚肉鮮嫩」「湯頭清爽」，
任何一道魚料理、任何一鍋湯都能套，讀完對「要不要吃這個」沒有幫助。

**原因之一是我自己寫的**：原本的 `@Guide` 描述列出「熱量、等待時間、價格」當提示，
反而害模型整批抓同一個維度。

**修正**：改成直接把空話列為禁用，並要求扣回這道菜本身。負面例子對小模型的效果
比正面指示明顯很多。優點另外要求「至少一則要講出決定得了的事」：
份量夠不夠飽、價位多少、多久吃得到、什麼身體狀態適合吃。

熱量不當賣點；健康面向可以講，但要指名食材與它帶來什麼
（「配菜有木耳，纖維補得到」），而不是「營養豐富」。

### 問題 11：MKLocalSearch 會回一千公里外的店

**現象**：在台北搜「豬肉親子丼」，列出日本飯塚市 1306 公里、大阪 1716 公里、
札幌 2693 公里的店。標題寫著「附近的」，內容是跨海。

**原因**：`MKLocalSearch.Request.region` 對 MapKit 而言只是**建議**，不是硬性條件。
本地沒有相符店家時它會擴大範圍到全世界。

**修正**：自己過濾掉 15 公里以外的結果。十五公里已經涵蓋一般都會區跨區通勤，
再遠就不是「順便去吃」的距離。過濾後為空就顯示找不到，並建議換更常見的關鍵字。

### 效能量測：產生一次菜單要多久

答案是 **17 到 20 秒**，遠低於兩分鐘。

#### 一個被自己推翻的結論

第一次量測（每種條件只跑兩次）得到 14.1 / 19.5 / 32.2 秒，看起來是「要越少反而越慢」，
當時的解釋是 prompt 與 schema 的數字打架。這個結論**是錯的**。

後來用同一個執行檔重跑同樣的八道條件，變成 14.5 秒。同樣的二進位檔、同樣的輸入，
結果差了兩倍以上，代表那個 32 秒是雜訊，不是效應。兩次取樣不足以下結論。

#### 重做的量測

改成每種條件跑三次，並同時記錄輸出總字數：

| prompt 要求道數 | 平均耗時 | 實際回幾道 | 輸出總字數 |
|---|---|---|---|
| 12 道 | 17.1 秒 | **12 道** | 683 字 |
| 10 道 | 20.5 秒 | **12 道** | 1024 字 |
| 8 道 | 18.2 秒 | **12 道** | 747 字 |

兩個關鍵事實：

1. **不論 prompt 寫幾道，回來的一律是 12 道。** `@Generable` 的 `.count(12)` 是硬性約束，
   prompt 裡的數字模型不理。三種條件下模型做的事其實一樣多。
2. **耗時跟輸出字數走，不跟要求的道數走。** 最慢的是話最多的那次（1024 字 / 20.5 秒），
   不是要求最少的那次。粗估約 10 秒固定開銷加上每 100 字約 1 秒，
   但只有三個資料點，不必當成精確公式。

`respond(to:generating:)` 的 `includeSchemaInPrompt` 預設為 true，schema 會被渲染成文字
送進 prompt，所以傳不一樣的數字會讓 prompt 自相矛盾。實測對速度沒有明顯影響，
但沒有理由這樣寫，`EngineRouter.suggest(prompt:count:)` 的註解已改成說明這一點。

**教訓**：兩次取樣量不出效能結論。差兩倍的數字看起來很有說服力，實際上只是雜訊。

### 新增功能：候選清單可以自訂

原本只有轉盤結果頁能「找附近有賣的店」，結果頁一關就回不去了，
要查同一道菜得重轉一次。現在候選清單每張卡展開後都有三個按鈕：

- **找附近** — 直接對這一道開地圖搜尋
- **改名** — 模型偶爾取怪名字，或想換成常去那家店的說法
- **刪除** — 拿掉不想吃的，轉盤跟著更新（剩兩道就不給刪，轉盤至少要兩格）

刪除或改名後會重設轉盤角度，因為格數變了，之前算好的停止角度沒有意義。

## 十、轉盤格數可自選

主畫面「產生菜單」上方加了格數選擇器：4 / 6 / 8 / 10 / 12，預設 8，設定會保留。

### 為什麼上限是 12

`FoodSuggestionList` 的 `.count(12)` 由 `@Generable` 在**編譯期**寫死，
執行時沒辦法換 schema，所以一次拿得到的候選最多 12 道。

### 為什麼改格數不用重新產生

`RotateViewModel` 把模型給的完整候選存在 `allItems`，畫面用的 `items` 是
`allItems.prefix(wheelSlots)` 算出來的。只留截斷結果就回不去了：
從 4 格改回 8 格時沒有東西可以補。分開存之後兩個方向都能即時調整。

湊不滿選定格數時（例如選 12 但模型只給得出 6 道不重複的），畫面會說明原因並建議
重新產生或把格數調低，而不是默默顯示比較少的格數。

### 問題 12：prompt 塞爆 context window

**現象**：加完格數功能後測 12 格，直接產生失敗，訊息是
「這次的需求太長，換短一點的描述再試」，也就是 `exceededContextWindowSize`。

**原因是我自己造成的**。前面幾輪為了修料理類型、多樣性、優缺點品質，
一路往 `PromptFactory.role` 加規則，加到九條而且每條都很長，
`@Guide` 的描述也越寫越細（優點那條一度接近 150 字）。
`includeSchemaInPrompt` 預設為 true，這些文字全部會連同 schema 一起送進 prompt，
最後超出裝置模型的 context window。

**修正**：規則從九條壓到八條並全部改寫成短句，`@Guide` 描述砍到剩約 160 字，
role 壓到約 410 字。約束的內容都保留，只是不再囉唆。

**教訓**：`@Guide` 的描述不是免費的，它會進 prompt。
要加約束之前先想想能不能改在程式層做，
料理形式去重（`FoodItem.dishForm` + `normalized`）就是搬到程式層之後
既穩定又不佔 prompt 空間的例子。

### 已知限制

裝置端模型要湊出 12 道彼此不同的日式料理有困難，實測常常只給得出 6 到 8 道不重複的。
12 格比較適合搭配範圍寬的需求（例如「宵夜」），或改用自架的大模型。

## 十一、三層程式化把關：模型管不住的事就別交給模型

第九章到這裡累積出一個明確的教訓：**同一類問題用 prompt 修三輪還修不好，就該搬到程式層。**
裝置端模型只有約三十億參數，對「不要出現什麼」這種否定條件遵守得很差，
而且同一段 prompt 跑兩次結果差很多，沒有辦法當成保證。

目前有三層確定性的把關，全部有測試。

### 第一層：`DietaryFilter` — 需求沒被遵守

**問題 13**：輸入「清爽一點」，模型回鹽酥雞、雞排、海鮮煎餅。

原因在規則的寫法：`1. 使用者指定類型或限制（日式、素食、不吃牛）時…`，
三個例子全是菜系或飲食禁忌，「清爽」屬於口味與油膩程度，不在這個框裡，
模型就不當成硬條件。

先試著改 prompt，明確寫「說清爽就不能出現油炸或油煎，鹽酥雞、雞排、煎餅都不行」。
結果鹽酥雞、雞排確實消失，換成**麻辣海鮮湯、辣炒蝦仁、蚵仔煎** —
點名的「煎」還是出現，而且「辣」是隔壁規則的內容，被串過來了。

改成程式層：從需求字串偵測限制，再用菜名關鍵字排除。
支援清爽／不油、不辣、素食、不吃牛、不吃豬、海鮮過敏。**9 項測試全過。**

原則是**寧可漏放不要誤殺**：判斷不出來的一律保留，
全部被濾光時退回原清單，因為空轉盤比不夠精準更沒用。

### 第二層：主食材上限 — 同食材換煮法

**問題 14**：飲食過濾生效後暴露反向問題，一輪回了七道有五道是蝦或蟹
（蝦仁麵、蝦仁鍋、蟹餃湯、蟹仁飯、蟹羹）。料理形式全都不同，順利通過形式去重，
但轉盤上等於只有兩種選擇。

加上 `mainIngredient` 與食材上限，跟形式上限一起漸進放寬。

**第一版寫錯了**：`mainIngredient` 取名稱第一個字，遇到「**蒜蓉**蝦仁湯」判成「蒜」，
於是四道蝦仁料理全部通過上限，畫面上出現四格全是蝦仁。
改成在整個名稱裡找食材關鍵字（具體的排前面，「鮭魚」不會先被「魚」比中），
找不到才退回第一個字。**測試涵蓋九種前綴修飾語，全過。**

### 第三層：`PointSanitizer` — 優缺點在講店家

**問題 15**：kuoyo 指出「需要排隊」是店家的事，不是料理的事。
排隊、服務、裝潢、營業時間換一家店結論就不一樣，對「要不要吃這道菜」沒有幫助；
「營養豐富」「鮮嫩」「性價比高」則是換哪道菜都成立，一樣沒有資訊。

這些早就寫進 prompt 了，實測連續多輪還是會冒出來，所以改成程式層清理：
命中店家字眼或空泛稱讚就整句丟掉，全部被清光時就留空
（UI 對空清單已有處理，寧可少一段也不要端出無關的話）。

**刻意不把「店家」兩個字列入關鍵字**：
「肥肉比例看店家運氣」講的是這道菜本身的變異度，那是有用的資訊，不該被誤殺。
**10 項測試全過。**

### 還在的限制

這三層擋掉的是可以用規則描述的錯誤。模型的幻覺擋不掉，
例如把珍珠奶茶當成「清爽」的選項，還說它的缺點是「油炸餡料」。
要更好的品質就得換更大的模型，設定頁的自架模型就是為此而留。

## 十二、要主食不要小菜，以及 Dynamic Island 載入條

2026-08-10。8/9 的實測留下兩個問題：抽到「燙青菜佐蒜蓉」沒辦法拿去找餐廳，
以及產生要等 20 到 28 秒（內建模型 28s、自架 gemma 20s），
離開 App 就完全不知道好了沒。

### 問題 16：模型回小菜不回主食

「清爽一點」這種需求會逼模型避開油炸與熱炒，剩下的安全牌就是涼拌與燙青菜，
**越聽話的模型越容易掉進去**。使用者要的是「一份就是一餐」的東西：
義大利麵、拉麵、咖哩、小火鍋、炸雞、漢堡。

照第十一節的原則分三層處理：

1. **收窄 schema**：`FoodItem.categories` 拿掉「湯品」與「甜點」（16 類剩 14 類）。
   裝置模型的 `.anyOf` 會直接擋住，自架模型也少了兩個可以逸出的選項。
   能當一餐的湯（藥燉排骨）本來就進得了「台式」，不會因此不見。
   舊歷史紀錄存的是 `String`，不需要 migration。
2. **prompt**：role 加一條「每一道都要是吃得飽的一餐」，正反例都給
   （負面例子對小模型比較有效，這點在問題 8 就驗證過）。
   同時把原本的規則 2 與 3 併成一條，總條數不變，context 帳面打平。
   `FoodItem.name` 的 `@Guide` 也改成「能當一餐的主食名稱」並附兩個例子。
3. **`MainDishFilter`**：程式層的確定性把關。

`MainDishFilter` 的關鍵設計是**小菜字眼分兩級**。第一版寫成一律淘汰，
測試立刻抓到誤殺：「涼拌雞絲麵」被砍掉了，而那正是「清爽」需求下最該留的答案。

- `hardSide`（燙青菜、味噌湯、海帶芽、泡菜、毛豆…）：不管有沒有主食形式都淘汰。
  必要，因為「味噌湯」含 `湯`、「海帶芽湯」含 `湯`，光看形式關鍵字會放行。
- `softSide`（佐、涼拌、醃）：**只有在沒有主食形式時才算小菜**。
  涼拌雞絲麵、椒麻雞佐白飯、醃雞腿飯都留得住，涼拌木耳、醃蘿蔔照樣砍掉。

`apply(to:minimum:)` 先嚴後鬆，跟 `normalized(minimum:)` 同一套想法：
先要求有明確主食形式，湊得滿最低格數就用這一份；湊不滿才退到「只砍明確小菜」。
會走到放寬層是因為模型這輪給的菜名不在已知形式裡（三杯雞、宮保雞丁），
這時候寧可漏放也不要誤殺。

### 問題 17：gemma 混韓文與簡體

`gemma3n:e4b` 會在中文清單裡冒出韓文，`qwen2.5:14b` 則偶發簡體。
新增 `TextNormalizer`，分工是**看得懂的就轉換，看不懂的就丟掉**：

- 諺文、假名、西里爾字母 → 整道淘汰。韓文菜名沒辦法自動變成台灣吃得到的料理，
  留著只會是按不下去的一格。只認整套文字系統，菜名裡夾英數字（`A餐`）不算。
- 簡體 → 用 ICU 的 `Hans-Hant` transform（`CFStringTransform`）轉繁體。
  **它是詞感知的**：`拉面 → 拉麵`、`面包 → 麵包` 都對，但詞庫沒收的組合會原封不動
  （`牛肉面`、`意大利面` 實測都不變），而且用的是大陸譯名（`咖喱`、`豆干 → 豆乾`）。
  所以後面再補一輪台灣用語對照表，最後在**菜名**收尾把 `面` 換成 `麵`。

`面 → 麵` 刻意只做在菜名。優缺點會出現「表面酥脆」，一律替換就變成「表麵酥脆」，
兩邊的風險不對稱，所以 `normalizeName` 與 `normalizeSentence` 分成兩個函式。

轉換要在**去重之前**做：同一輪回過「涼拌小黄瓜」與「涼拌小黃瓜」，
不先正規化就會被當成兩道不同的菜，轉盤上出現兩格一模一樣的東西。

**88 項測試全過**（macOS 直接編譯真實原始檔）。

### Dynamic Island 載入條

沒有 streaming 就拿不到真實百分比。設計上**把進度條與文字的來源分開**：

- **進度條走時間估計**，用 `ProgressView(timerInterval:)` 讓系統自己畫。
  Live Activity 的更新有頻率限制，不可能每秒推一次。
  估計值取自**上一次同一個引擎實際花的秒數**（`AppSettings.estimatedDuration(for:)`，
  clamp 在 8…60；沒有紀錄時裝置 18s、自架 25s）。同樣是自架模型，
  跑 14B 跟跑 0.8B 差好幾倍，寫死常數不會準。
- **文字走真實階段**：要補一輪、換了引擎都如實反映。
  超過估計時間就換成「快好了…」——進度條可以估，但文字不能騙人。

階段只有一個來源：`RotateViewModel.setStage` 設定，Live Activity 跟著更新。
分兩個地方各記一份遲早會對不起來。

**背景執行時間是必要的，不是加分項。** Live Activity 的意義就是讓人可以離開 App，
但一離開 `URLSession` 就會被暫停，島上的進度條卻還在跑。
所以 `LoadingActivityController` 把 `beginBackgroundTask` 跟 Live Activity 綁在一起開收。

實作上踩到的三件事：

1. **`INFOPLIST_KEY_NSExtensionPointIdentifier` 沒有作用**。build 過了、appex 也嵌進去了，
   但 dump 出來的 `Info.plist` 裡根本沒有 `NSExtension` 這個 dict，
   extension 不會被當成 widget 認出來。改成在專案根目錄放 `FoodRotateWidget-Info.plist`
   並用 `INFOPLIST_FILE` 指過去（不能放進同步資料夾，理由同決策 1）。
2. **`ActivityKit.Activity` 沒有宣告 `Sendable`**（查了 SDK 的 `.swiftinterface`），
   而 `update`／`end` 都是 nonisolated async。把它存成 MainActor 隔離的屬性再送進去，
   Swift 6 直接擋下來。解法是**只存 `id`**，要用的時候在 nonisolated 情境下從
   `Activity.activities` 查回來，完全不需要 `nonisolated(unsafe)`。
3. **extension 讀不到 App 的 `AccentColor`**。asset catalog 只屬於 App target，
   `Color.accentColor` 在 widget 裡退回系統藍——實測島上的進度條真的是藍色的。
   目前在 `LoadingLiveActivity.swift` 寫死一份並註明出處，改色要改兩邊。

共用型別 `Shared/GenerationActivityAttributes.swift` 不走同步群組：
同步群組只掛在單一 target，所以這個檔用傳統的 `PBXFileReference` ＋ 兩個 `PBXBuildFile`，
分別加進兩個 target 的 Sources phase。

### 自架模型改成清單選擇

手打模型名稱太容易錯：`gemma3n:e4b` 少一個冒號、tag 打成 `:latest`，
要等到產生階段才會拿到 404，而那時候使用者已經等了幾十秒。
改成位址填好就自動打 `/v1/models` 把清單抓回來讓人選（`.pickerStyle(.navigationLink)`，
自架的機器上常常掛著十幾個模型，選單會長到蓋住畫面）。

手動輸入的退路必須留著：`listModels()` 對形狀不標準的 `/v1/models` 會回空陣列，
那種後端照樣可以正常產生菜單。目前設定的模型即使伺服器上沒有也要留在選項裡，
否則 Picker 找不到對應的 tag 會顯示空白，看起來像設定不見了。

### 這一輪的驗證

| 項目 | 方式 | 結果 |
|---|---|---|
| 過濾與語言層 | macOS 編譯真實原始檔 | 88 項全過 |
| Debug／Release build | `xcodebuild` | 通過，零錯誤零警告 |
| Debug 後門未進 Release | `strings` 掃 Release binary | 4 個參數都是 0 |
| appex 嵌入與 `NSExtension` | dump 安裝後的 `Info.plist` | 正確 |
| Dynamic Island | 模擬器截圖（啟動 Safari 把 App 切到背景） | compact 進度條在跑，橘色，結束後自動收掉 |
| 裝置模型實跑「清爽一點」 | 模擬器 `-autoGenerate` | 沒有撞 context window；6 道全是主食 |
| 設定頁模型清單 | 本機 mock `/v1/models` ＋ `-selfHostedBaseURL` | 正確顯示成推進式清單 |

裝置模型那輪回的是蘿蔔絲雞飯、雞胸肉沙拉、芋頭粥、蟹肉餃子、蟹肉湯圓、雞肉湯圓——
沒有一道是小菜。

**還沒驗到的**：自架 gemma 的實跑。這台 Mac 連不到 `<內網主機>:11434`
（同一個網路才行），韓文與簡體的處理只有單元測試層級的證據，沒有端到端的。

## 十三、怎麼跑起來

App 已經裝在 iPhone 17 Pro 模擬器上（bundle id `com.kuoyo.foodrotate`）。
從原始碼重新建置：

```bash
xcodebuild -project FoodRotate.xcodeproj -scheme FoodRotate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

或直接用 Xcode 開 `FoodRotate.xcodeproj` 按 Run。

**要讓兩個引擎真的能用**：

- **裝置內建模型**：這台 Mac 的 Apple Intelligence 已開啟且模型下載完成，
  模擬器上可以直接用。換一台 Mac 或重灌後要重新開啟
  （系統設定 → Apple Intelligence 與 Siri）。真機則需要 iPhone 15 Pro 以上。
- **自架模型**：到設定頁填伺服器位址與模型名稱，按「測試連線」確認。
  跑在同一台 Mac 上的服務，模擬器可以直接用 `http://127.0.0.1:<port>`；
  真機則要填 Mac 的區網 IP，且兩台要在同一個網路。
