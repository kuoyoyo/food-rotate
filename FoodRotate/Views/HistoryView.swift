import SwiftData
import SwiftUI

/// 轉盤歷史。點一筆可以把整組清單原樣還原回轉盤。
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpinRecord.date, order: .reverse) private var records: [SpinRecord]

    /// 還原後要跳回轉盤分頁，所以把選擇往上拋。
    let onRestore: (SpinRecord) -> Void

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
        ContentUnavailableView(
            "還沒有紀錄",
            systemImage: "clock.arrow.circlepath",
            description: Text("轉過的每一次都會存在這裡，可以直接還原同一組清單重轉。")
        )
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
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ record: SpinRecord) -> some View {
        HStack(spacing: 12) {
            Text(record.winner?.displayEmoji ?? "🍽️")
                .font(.system(size: 28))
                .frame(width: 42, height: 42)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(record.winnerName)
                    .font(.subheadline.weight(.semibold))
                Text(record.prompt.isEmpty ? "沒有指定條件" : record.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(record.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.counterclockwise")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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
