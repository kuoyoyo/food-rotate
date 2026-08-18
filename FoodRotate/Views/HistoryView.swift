import SwiftData
import SwiftUI

/// 轉盤歷史。點一筆可以把整組清單原樣還原回轉盤。
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpinRecord.date, order: .reverse) private var records: [SpinRecord]

    /// 還原後要跳回轉盤分頁，所以把選擇往上拋。
    let onRestore: (SpinRecord) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var storage = HistoryStorage.shared

    var body: some View {
        Group {
            if records.isEmpty {
                empty
            } else {
                VStack(spacing: 0) {
                    // 保存壞掉的時候在這裡說一句。
                    //
                    // **非阻擋**：不是彈窗、不擋操作、正常時完全不佔位。
                    // 放在歷史頁而不是全 App，因為後果只發生在這裡 ——
                    // 提示要出現在使用者會受影響的地方，不是最顯眼的地方。
                    if let notice = storage.notice {
                        InfoNotice(symbol: "exclamationmark.triangle", text: notice)
                            .padding(.horizontal, Theme.space16)
                            .background(Theme.pageBackground(for: colorScheme))
                    }
                    list
                }
            }
        }
        .navigationTitle("歷史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("清除全部紀錄", systemImage: "trash", role: .destructive) {
                            deleteAll()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var empty: some View {
        // 用 builder 形式而不是 `ContentUnavailableView("…", systemImage:)`：
        // 後者的標題吃系統 primary、說明吃 secondary，從外面套 `foregroundStyle`
        // 蓋不掉。三個部件的顏色規格各自指定（圖示與說明次要、標題主文字），
        // 只有這個形式套得進去。
        ContentUnavailableView {
            Label {
                Text("還沒有紀錄")
                    .foregroundStyle(Theme.text(for: colorScheme))
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.textSecondary(for: colorScheme))
            }
        } description: {
            Text("轉過的每一次都會存在這裡，可以直接還原同一組清單重轉。")
                .foregroundStyle(Theme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.pageBackground(for: colorScheme))
    }

    private var list: some View {
        List {
            ForEach(records) { record in
                // 能還原的才做成按鈕。
                //
                // 餐廳紀錄沒有「還原」這個概念（存下來的店家資料會過期），
                // 舊的、解不開的紀錄還原出來是空清單 —— 兩種都不該有按鈕，
                // **也不該有一顆按了沒反應的按鈕**。那正是我們拿掉死按鈕的理由。
                if record.canRestore {
                    Button {
                        Haptics.buttonTap()
                        onRestore(record)
                    } label: {
                        row(record)
                    }
                    .buttonStyle(.plain)
                    .dishListRowStyle(for: colorScheme)
                } else {
                    // **不加任何其他視覺差別**：不淡化、不加鎖、不改字色。
                    // 有沒有還原圖示本身就是差別，再淡化是在同一件事上講第二次；
                    // 而且淡化在這套系統裡代表「停用」，但這一列沒有壞也沒有失效。
                    row(record)
                        .dishListRowStyle(for: colorScheme)
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .dishListBackground(for: colorScheme)
    }

    private func row(_ record: SpinRecord) -> some View {
        DishListRow(
            emoji: record.winner?.displayEmoji ?? "🍽️",
            title: record.winnerName,
            subtitle: record.prompt.isEmpty ? "沒有指定條件" : record.prompt,
            // 舊版紀錄的 JSON 少了欄位、解不開（見 `SpinRecord.items`），
            // 那時候 `winner` 是 nil，就沒有角標可顯示。
            badgeSource: record.winner,
            // 歷史頁只顯示菜系：右邊已經有時間與還原符號，再加吃法會擠掉菜名。
            showsFormBadge: false
        ) {
            HStack(spacing: Theme.space8) {
                Text(record.date, format: .dateTime.month().day().hour().minute())
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary(for: colorScheme))

                // 這個符號是「點這一列會還原」的唯一提示，所以**只有真的能還原時才出現**。
                // 沒有那個資訊就不畫那個位置 —— 跟 S5-B「無菜系標籤時不顯示角標」同一條原則。
                if record.canRestore {
                    Image(systemName: "arrow.counterclockwise")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.sauce(for: colorScheme))
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(records[index])
        }
        HistoryStorage.shared.save(modelContext)
    }

    private func deleteAll() {
        for record in records {
            modelContext.delete(record)
        }
        HistoryStorage.shared.save(modelContext)
    }
}
