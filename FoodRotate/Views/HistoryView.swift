import SwiftData
import SwiftUI

/// 轉盤歷史。點一筆可以把整組清單原樣還原回轉盤。
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpinRecord.date, order: .reverse) private var records: [SpinRecord]

    /// 還原後要跳回轉盤分頁，所以把選擇往上拋。
    let onRestore: (SpinRecord) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if records.isEmpty {
                empty
            } else {
                list
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
                Button {
                    Haptics.buttonTap()
                    onRestore(record)
                } label: {
                    row(record)
                }
                .buttonStyle(.plain)
                .dishListRowStyle(for: colorScheme)
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

                // 保留這個符號：它是「點這一列會還原」的唯一提示。
                // 規格的列表沒有列到它，但拿掉是減少一個功能的提示，不是套色。
                Image(systemName: "arrow.counterclockwise")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.sauce(for: colorScheme))
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(records[index])
        }
        try? modelContext.save()
    }

    private func deleteAll() {
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }
}
