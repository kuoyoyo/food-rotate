import Foundation
import Testing

@testable import FoodRotate

/// 候選清單左滑「這輪不要」的位移與門檻。
///
/// 這支測試的由來值得記著：上一版這裡用 `.swipeActions`，
/// 而那個修飾符**只在 `List` 的 row 上有作用** —— 掛在 `VStack` 的子 view 上
/// 編得過、不當機、沒有警告，但什麼都不會發生。PM 實機左滑兩次才發現。
///
/// 手勢本身沒有觸控就驅動不了，但**位移與門檻的判斷是純數字**，
/// 抽出來就測得到。至少「滑多遠會怎樣」這件事不必再靠人去滑。
@Suite("清單左滑")
struct RowSwipeTests {

    // MARK: - 位移

    @Test("只往左滑，右滑不會把列拉出容器")
    func 右滑不動() {
        #expect(RowSwipe.offset(base: 0, translation: 80) == 0)
        #expect(RowSwipe.offset(base: 0, translation: 500) == 0)
    }

    @Test("往左跟手")
    func 左滑跟手() {
        #expect(RowSwipe.offset(base: 0, translation: -40) == -40)
        #expect(RowSwipe.offset(base: 0, translation: -120) == -120)
    }

    @Test("拉到底就不再跟手，讓人知道到底了")
    func 有上限() {
        #expect(RowSwipe.offset(base: 0, translation: -1000) == -RowSwipe.maxPull)
    }

    @Test("已經滑開時從開啟位置繼續，不會跳回原點")
    func 從開啟位置續拖() {
        let base = -RowSwipe.actionWidth
        #expect(RowSwipe.offset(base: base, translation: -30) == base - 30)
        // 往回推也要跟手，推過頭就是收合。
        #expect(RowSwipe.offset(base: base, translation: 200) == 0)
    }

    // MARK: - 放手之後

    @Test("滑一點點就彈回去")
    func 沒過門檻收回() {
        #expect(RowSwipe.resolve(offset: 0) == .closed)
        #expect(RowSwipe.resolve(offset: -10) == .closed)
        #expect(RowSwipe.resolve(offset: -(RowSwipe.actionWidth / 2) + 1) == .closed)
    }

    @Test("過了按鈕寬度一半就停在開啟位置")
    func 停在開啟位置() {
        #expect(RowSwipe.resolve(offset: -RowSwipe.actionWidth / 2) == .opened)
        #expect(RowSwipe.resolve(offset: -RowSwipe.actionWidth) == .opened)
        #expect(RowSwipe.resolve(offset: -(RowSwipe.performThreshold - 1)) == .opened)
    }

    @Test("一口氣滑過頭就直接執行，不必再點按鈕")
    func 大幅滑動直接執行() {
        #expect(RowSwipe.resolve(offset: -RowSwipe.performThreshold) == .perform)
        #expect(RowSwipe.resolve(offset: -RowSwipe.maxPull) == .perform)
    }

    @Test("門檻的大小關係要成立")
    func 門檻順序合理() {
        // 弄反的話「滑到底」會變成「停在開啟位置」，而使用者明明滑得很用力。
        #expect(RowSwipe.actionWidth / 2 < RowSwipe.performThreshold)
        #expect(RowSwipe.performThreshold <= RowSwipe.maxPull)
    }
}
