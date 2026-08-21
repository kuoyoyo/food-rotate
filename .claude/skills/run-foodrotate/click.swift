// 對模擬器視窗送滑鼠事件。
//
// 為什麼需要這支：Simulator 不接受 AppleScript 的 `click at`（回 -25204），
// 而 `xcrun simctl` 從來就沒有 tap 子命令。CGEvent 是這台機器上唯一
// 不必額外安裝東西（idb / cliclick）就能點到模擬器的路。
//
// 座標是 macOS 螢幕座標，換算由 driver.sh 負責。
//
//   click <x> <y>                  點一下
//   click <x1> <y1> <x2> <y2>      按住拖曳（捲動、左滑都用這個）

import CoreGraphics
import Foundation

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

let args = CommandLine.arguments

if args.count == 3, let x = Double(args[1]), let y = Double(args[2]) {
    let p = CGPoint(x: x, y: y)
    post(.mouseMoved, p);     usleep(80_000)
    post(.leftMouseDown, p);  usleep(70_000)
    post(.leftMouseUp, p)

} else if args.count == 5,
          let x1 = Double(args[1]), let y1 = Double(args[2]),
          let x2 = Double(args[3]), let y2 = Double(args[4]) {
    let start = CGPoint(x: x1, y: y1)
    let end = CGPoint(x: x2, y: y2)
    post(.mouseMoved, start);    usleep(80_000)
    post(.leftMouseDown, start); usleep(60_000)
    // 一次跳到終點 SwiftUI 會判成點擊而不是拖曳，所以要分格送。
    let steps = 24
    for i in 1...steps {
        let f = Double(i) / Double(steps)
        post(.leftMouseDragged,
             CGPoint(x: x1 + (x2 - x1) * f, y: y1 + (y2 - y1) * f))
        usleep(12_000)
    }
    usleep(40_000)
    post(.leftMouseUp, end)

} else {
    FileHandle.standardError.write(
        "usage: click <x> <y> | click <x1> <y1> <x2> <y2>\n".data(using: .utf8)!)
    exit(1)
}
