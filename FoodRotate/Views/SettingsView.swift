import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var store = CustomFoodStore.shared

    var body: some View {
        Form {
            wheelSection
            librarySection
            mapSection
            aboutSection
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 轉盤

    private var wheelSection: some View {
        Section {
            Picker("轉盤格數", selection: $settings.wheelSlots) {
                ForEach(WheelCapacity.allowedSlots, id: \.self) { count in
                    Text("\(count) 格").tag(count)
                }
            }
        } header: {
            Text("轉盤")
        } footer: {
            Text("格數多一點選擇多，少一點比較好決定。轉盤畫面上也可以直接改。")
        }
    }

    // MARK: 資料庫

    private var librarySection: some View {
        Section {
            NavigationLink {
                MyListView()
            } label: {
                LabeledContent("我的清單") {
                    Text(store.customizationCount == 0 ? "沒有改動" : "改了 \(store.customizationCount) 項")
                }
            }
            LabeledContent("目前可抽", value: "\(store.pool.count) 道")
            LabeledContent("內建料理", value: "\(FoodLibrary.all.count) 道・\(FoodLibrary.categories.count) 類")
        } header: {
            Text("菜色資料庫")
        } footer: {
            Text("料理清單內建在 App 裡，完全離線、不需要網路也不會上傳任何資料。你自己加的料理也只存在這台裝置上。只有「找附近的店」會用到定位與網路。")
        }
    }

    // MARK: 地圖

    private var mapSection: some View {
        Section {
            Picker("導航用", selection: $settings.preferredMapApp) {
                ForEach(MapApp.allCases) { app in
                    Text(app.displayName).tag(app)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("地圖")
        } footer: {
            Text("在店家清單上長按可以臨時改用另一個。沒裝 Google 地圖時會改開網頁版，不會沒有反應。")
        }
    }

    // MARK: 關於

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: Bundle.main.appVersion)
            CopyrightFooter()
                .listRowBackground(Color.clear)
        } header: {
            Text("關於")
        }
    }
}

// MARK: - 版權標示

/// 版權標示。主畫面、結果頁與設定頁都會出現。
struct CopyrightFooter: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("食物轉盤 Food Rotate")
                .font(.footnote.weight(.semibold))
            Text("Claude Code 製作 · kuoyo 設計")
                .font(.caption)
                .foregroundStyle(.secondary)
            // 用 verbatim，否則 SwiftUI 會把 Int 當數字格式化成「2,026」。
            Text(verbatim: "© \(Calendar.current.component(.year, from: .now)) kuoyo")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
