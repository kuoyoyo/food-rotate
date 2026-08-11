import Foundation
import Testing

@testable import FoodRotate

/// 設計 token 的數值規則。
///
/// 這支測試存在的理由是 `設計規格-Theme-v1` 第一節那件事：PM 定案八色時沒有檢查文字對比，
/// 蛋黃與抹茶配白字只有 2.5，遠低於 4.5 的門檻，一路到規格階段才被發現。
/// **對比不合格是看不出來的那種壞** —— 畫面照常顯示，只是有些人讀不到。
/// 所以門檻要用測試釘住，不能靠下次有人想到要量。
@Suite("設計 token")
struct DesignTokenTests {

    // MARK: - WCAG 對比

    /// 相對亮度（WCAG 2.x）。
    private static func luminance(_ color: DesignTokens.RGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red)
            + 0.7152 * channel(color.green)
            + 0.0722 * channel(color.blue)
    }

    private static func contrast(_ a: DesignTokens.RGB, _ b: DesignTokens.RGB) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    /// 轉盤菜名是 12–14pt semibold，不算大字，門檻是 AA 的 4.5:1。
    private static let threshold = 4.5

    @Test("每一格的菜名對比都過 AA，四種格數、深淺兩底全部")
    func 轉盤每格的文字對比都合格() {
        for count in WheelCapacity.allowedSlots {
            for surface in [DesignTokens.Surface.light, .dark] {
                for (index, slot) in DesignTokens.wheelSlots(count: count, on: surface).enumerated() {
                    let ratio = Self.contrast(slot.fill, slot.ink.color)
                    #expect(
                        ratio >= Self.threshold,
                        "\(count) 格第 \(index) 格（\(surface)）對比只有 \(ratio)"
                    )
                }
            }
        }
    }

    @Test("表面與主色的對比也要過")
    func 表面與主色的對比合格() {
        // 深色主色是規格補進來的：淺色那個 #9B3B2C 疊在深卡片上只有 2.36。
        #expect(Self.contrast(DesignTokens.sauce, DesignTokens.Light.card) >= Self.threshold)
        #expect(Self.contrast(DesignTokens.Dark.sauce, DesignTokens.Dark.card) >= Self.threshold)

        #expect(Self.contrast(DesignTokens.Light.text, DesignTokens.Light.card) >= Self.threshold)
        #expect(Self.contrast(DesignTokens.Light.text, DesignTokens.Light.pageBackground) >= Self.threshold)
        #expect(Self.contrast(DesignTokens.Dark.text, DesignTokens.Dark.card) >= Self.threshold)
        #expect(Self.contrast(DesignTokens.Dark.text, DesignTokens.Dark.pageBackground) >= Self.threshold)
    }

    // MARK: - 取色順序

    @Test("取色順序表跟規格一字不差")
    func 取色順序符合規格() {
        func order(_ count: Int) -> String {
            DesignTokens.slotOrder(for: count)
                .map { "\($0.index)\($0.isLightVariant ? "+" : "")" }
                .joined(separator: ",")
        }

        #expect(order(4) == "0,2,4,6")
        #expect(order(6) == "0,2,3,4,6,7")
        #expect(order(8) == "0,1,2,3,4,5,6,7")
        #expect(order(10) == "0,1,2,3,4,5,6,7,0+,2+")
        #expect(order(12) == "0,1,2,3,4,5,6,7,0+,2+,3+,1+")
    }

    @Test("同一盤上不會出現兩塊一樣的顏色")
    func 每格顏色都不重複() {
        // 8 色配 10／12 格如果直接 index % 8 就會撞色，淺階變體就是為了解這個。
        for count in WheelCapacity.allowedSlots {
            for surface in [DesignTokens.Surface.light, .dark] {
                let fills = DesignTokens.wheelSlots(count: count, on: surface).map(\.fill)
                #expect(Set(fills.map(\.debugKey)).count == count, "\(count) 格（\(surface)）有撞色")
            }
        }
    }

    @Test("抽不滿格時也要有顏色可用")
    func 表外的格數不會當掉() {
        // 轉盤畫幾格是看抽到幾道菜，條件太嚴時可能只有 1–3 道，不會是 allowedSlots 裡的值。
        for count in [1, 2, 3, 5, 7, 13] {
            #expect(DesignTokens.wheelSlots(count: count, on: .light).count == count)
        }
        #expect(DesignTokens.wheelSlots(count: 0, on: .light).isEmpty)
    }

    // MARK: - 推導公式

    @Test("icon 加深公式推出來的值與規格相符")
    func icon加深公式符合規格() {
        // 規格第六節的推導表。其中蔥綠與青瓷兩列，規格印的值與公式算出來的差不到 4/255，
        // 是設計師工具的四捨五入雜訊（已回報 PM）。公式才是規格明定的定義，
        // 所以這裡用容差比對，而不是把表上的值抄成常數 —— 抄了就等於又多一份色票。
        let expected: [UInt32] = [
            0x993D25, 0xB47F28, 0x838F47, 0x456A56,
            0x3B6A76, 0x465A88, 0x765688, 0x8E4B2C,
        ]
        let tolerance = 4.0 / 255

        for (slot, hex) in zip(DesignTokens.wheelOnLight, expected) {
            let got = DesignTokens.deepenedForIcon(slot.fill)
            let want = DesignTokens.RGB(hex)
            #expect(abs(got.red - want.red) <= tolerance)
            #expect(abs(got.green - want.green) <= tolerance)
            #expect(abs(got.blue - want.blue) <= tolerance)
        }
    }

    @Test("HSB 換算來回一趟不會走鐘")
    func hsb來回轉換是可逆的() {
        // 手寫的換算（不用 UIColor，因為這個檔要能被 macOS 腳本一起編），
        // 所以要自己證明它沒寫錯。
        for slot in DesignTokens.wheelOnLight + DesignTokens.wheelOnDark {
            let (hue, saturation, brightness) = slot.fill.hsb
            let roundTrip = DesignTokens.RGB(
                hue: hue, saturation: saturation, brightness: brightness
            )
            #expect(abs(roundTrip.red - slot.fill.red) < 0.001)
            #expect(abs(roundTrip.green - slot.fill.green) < 0.001)
            #expect(abs(roundTrip.blue - slot.fill.blue) < 0.001)
        }
    }
}

private extension DesignTokens.RGB {
    /// 拿來當 `Set` 的鍵。浮點數直接比不安全，取到小數第三位就足夠分辨兩個不同的色票。
    var debugKey: String {
        String(format: "%.3f-%.3f-%.3f", red, green, blue)
    }
}
