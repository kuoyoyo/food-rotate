import Foundation
import SwiftData
import Testing

@testable import FoodRotate

/// 轉盤那一輪的非同步邊界（S6 P0-1）。
///
/// 這一組測試跟前面 43 支的性質不同：**它們測的是時機，不是數值。**
/// 缺陷在正常操作下不會出現 —— 要「按下轉盤 → 4.2 秒還沒到 → 改格數 → 再按一次轉」
/// 才踩得到，所以沒有辦法用截圖證明修好了，只能用一支**修之前會紅**的測試。
///
/// 時機由 `Gate` 控制：`WheelSpinner` 的等待被換成停在閘門前，
/// 測試決定什麼時候放行。這樣「舊的那一輪在新的一輪開始之後才醒來」
/// 就是一個可以精準重現的順序，而不是一個要碰運氣的競態。
@Suite("轉盤的非同步邊界", .serialized)
@MainActor
struct WheelSpinnerRaceTests {

    /// 讓所有等待停在同一個閘門前，由測試放行。
    actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []

        var waitingCount: Int { waiters.count }

        func wait() async {
            await withCheckedContinuation { waiters.append($0) }
        }

        /// 放行目前所有等待中的工作，依照它們抵達的順序。
        func releaseAll() {
            let pending = waiters
            waiters = []
            for continuation in pending { continuation.resume() }
        }

        /// 等到至少有 `count` 個工作抵達閘門，或等到逾時。
        ///
        /// **是「輪詢一個條件加上限」，不是「睡一個猜的秒數」。** 兩者差很多：
        /// 前者在快的機器上立刻回來、在慢的機器上多等一下；後者只是賭。
        ///
        /// 這裡踩過一個坑：原本用 `Task.yield()` 的忙迴圈，結果它會一直把自己
        /// 排回佇列前面，剛建立的工作**排不進來** —— 讓 2000 次也等不到。
        /// 真的睡 1 毫秒才會讓出執行機會。
        @discardableResult
        func waitUntilArrived(_ count: Int, timeout: Duration = .seconds(2)) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if waiters.count >= count { return true }
                try? await Task.sleep(for: .milliseconds(1))
            }
            return waiters.count >= count
        }
    }

    private static func spinner(gate: Gate) -> WheelSpinner {
        WheelSpinner(wait: { _ in await gate.wait() })
    }

    /// 讓已經排好的工作跑完。
    private static func settle() async {
        for _ in 0..<20 { try? await Task.sleep(for: .milliseconds(1)) }
    }

    /// 等到條件成立或逾時。用在「這件事應該要發生」的斷言前面。
    @discardableResult
    private static func waitUntil(
        _ condition: () -> Bool,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

    // MARK: - P0-1 的核心

    @Test("上一輪醒來時不得結束新的一輪，也不得執行自己的 completion")
    func 舊的一輪不能影響新的一輪() async {
        let gate = Gate()
        let spinner = Self.spinner(gate: gate)

        var finishedA = 0
        var finishedB = 0

        // A 起轉，停在第 11 格（12 格盤）。它會停在閘門前，還沒有結束。
        spinner.spin(segmentCount: 12, winner: 11) { finishedA += 1 }
        await gate.waitUntilArrived(1)

        // 使用者在 A 還在轉的時候改了格數 —— 現況下這條路徑會呼叫 reset()。
        spinner.reset()

        // B 起轉，只有 4 格。
        spinner.spin(segmentCount: 4, winner: 1) { finishedB += 1 }
        await gate.waitUntilArrived(1)

        // 現在放行：A 先醒來（它先到閘門），然後才輪到 B。
        await gate.releaseAll()
        await Self.settle()

        // 修好之前：A 醒來看到「正在轉」就把 B 結束掉，並執行 A 自己的 completion。
        #expect(finishedA == 0, "上一輪已經被 reset 掉了，它的 completion 不該執行")

        // B 還在轉（它自己的等待才剛被放行，這一輪由它自己結束）。
        await gate.releaseAll()
        await Self.waitUntil { finishedB == 1 }
        #expect(finishedB == 1, "新的一輪要能正常結束，而且只結束一次")
        #expect(finishedA == 0, "放行第二次之後，上一輪照樣不該執行")
    }

    @Test("reset 之後沒有再起轉，舊的一輪醒來不得復活任何狀態")
    func reset之後舊的一輪不得復活() async {
        let gate = Gate()
        let spinner = Self.spinner(gate: gate)

        var finished = 0
        spinner.spin(segmentCount: 8, winner: 3) { finished += 1 }
        await gate.waitUntilArrived(1)

        spinner.reset()
        await gate.releaseAll()
        await Self.settle()

        #expect(finished == 0)
        #expect(spinner.isSpinning == false)
        // reset 把停止角度歸零了，舊的一輪不該把自己的角度寫回去。
        #expect(spinner.restingAngle == 0)
    }

    @Test("同一輪只會結束一次")
    func 同一輪只結束一次() async {
        let gate = Gate()
        let spinner = Self.spinner(gate: gate)

        var finished = 0
        spinner.spin(segmentCount: 6, winner: 2) { finished += 1 }
        await gate.waitUntilArrived(1)

        await gate.releaseAll()
        await Self.waitUntil { finished == 1 }
        // 再放行一次（跨格觸覺那條 Task 也在閘門上，不該觸發第二次結束）。
        await gate.releaseAll()
        await Self.settle()

        #expect(finished == 1)
        #expect(spinner.isSpinning == false)
    }

    // MARK: - 驗收門檻：快速操作不得崩潰

    @Test("快速「起轉 → 改格數 → 再起轉」50 次不得崩潰，也不得抽出不在清單裡的菜")
    func 快速操作五十次() async throws {
        let gate = Gate()
        let spinner = Self.spinner(gate: gate)
        let model = RotateViewModel(spinner: spinner)

        let container = try ModelContainer(
            for: SpinRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        for _ in 0..<50 {
            // 12 格起轉：這一輪的中選位置可能落在第 5～11 格。
            model.wheelSlots = 12
            model.spin(saveTo: context)
            await gate.waitUntilArrived(1)

            // 還在轉的時候把盤縮到 4 格。舊的那一輪如果醒來時用「位置」去讀清單，
            // 這裡就是 index out of range。
            model.wheelSlots = 4
            model.spin(saveTo: context)
            await gate.waitUntilArrived(1)

            await gate.releaseAll()
            await Self.settle()

            // 有結果的話，那一道一定要還在現在的清單裡 —— 不能是上一輪的殘影。
            if let winner = model.winner {
                #expect(
                    model.items.contains(where: { $0.id == winner.id }),
                    "抽出來的菜必須來自現在這一份清單"
                )
            }

            model.spinner.reset()
            await gate.releaseAll()
            await Self.settle()
        }
    }
}
