// 사용법: swift scripts/make-default-pet.swift Resources/pets/default/spritesheet.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let (W, H, cellW, cellH, px) = (1536, 1872, 192, 208, 16)
let counts = [6, 8, 8, 4, 5, 8, 6, 6, 6]
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))

let body = CGColor(red: 0.96, green: 0.62, blue: 0.25, alpha: 1)   // 주황 몸통
let dark = CGColor(red: 0.2, green: 0.15, blue: 0.12, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let red = CGColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 1)
let green = CGColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1)

/// 셀 좌표계: (0,0) 이 셀의 좌하단 픽셀. 12 열 × 13 행.
func dot(_ row: Int, _ col: Int, _ x: Int, _ y: Int, _ color: CGColor) {
    guard (0..<12).contains(x), (0..<13).contains(y) else { return }
    ctx.setFillColor(color)
    let originX = col * cellW + x * px
    let originY = H - (row + 1) * cellH + y * px
    ctx.fill(CGRect(x: originX, y: originY, width: px, height: px))
}

/// 몸통: 가로 8, 세로 7 의 둥근 덩어리. dy 로 위아래, lean 으로 좌우 기울임.
func drawBody(row: Int, col: Int, dy: Int, lean: Int = 0, eyes: String = "open", extra: ((Int, Int) -> Void)? = nil) {
    let shape = [
        "..XXXXXX..",
        ".XXXXXXXX.",
        "XXXXXXXXXX",
        "XXXXXXXXXX",
        "XXXXXXXXXX",
        ".XXXXXXXX.",
        "..XX..XX..",
    ]
    for (r, line) in shape.reversed().enumerated() {
        for (c, ch) in line.enumerated() where ch == "X" {
            dot(row, col, c + 1 + lean, r + 1 + dy, body)
        }
    }
    let ey = 4 + dy
    switch eyes {
    case "closed":
        dot(row, col, 3 + lean, ey, dark); dot(row, col, 4 + lean, ey, dark)
        dot(row, col, 7 + lean, ey, dark); dot(row, col, 8 + lean, ey, dark)
    case "x":
        for (x, y) in [(3, ey + 1), (4, ey), (3, ey - 1), (7, ey + 1), (8, ey), (7, ey - 1)] { dot(row, col, x + lean, y, dark) }
        dot(row, col, 5 + lean, ey - 1, dark)
    default:
        dot(row, col, 3 + lean, ey, white); dot(row, col, 4 + lean, ey, dark)
        dot(row, col, 7 + lean, ey, white); dot(row, col, 8 + lean, ey, dark)
    }
    extra?(row, col)
}

// 0 idle: 천천히 숨쉬기
for c in 0..<counts[0] { drawBody(row: 0, col: c, dy: [0, 0, 1, 1, 0, 0][c], eyes: c == 4 ? "closed" : "open") }
// 1 running-right / 2 running-left: 기울여 뛰기
for c in 0..<counts[1] { drawBody(row: 1, col: c, dy: c % 2, lean: 1) }
for c in 0..<counts[2] { drawBody(row: 2, col: c, dy: c % 2, lean: -1) }
// 3 waving: 오른쪽 위에 손
for c in 0..<counts[3] { drawBody(row: 3, col: c, dy: 0) { r, col in
    dot(r, col, 10, [8, 9, 8, 7][c], body); dot(r, col, 11, [9, 10, 9, 8][c], body)
} }
// 4 jumping: 포물선
for c in 0..<counts[4] { drawBody(row: 4, col: c, dy: [0, 2, 4, 2, 0][c]) }
// 5 failed: X 눈, 떨림
for c in 0..<counts[5] { drawBody(row: 5, col: c, dy: 0, lean: c % 2 == 0 ? 0 : 1, eyes: "x") { r, col in
    dot(r, col, 10, 10, red); dot(r, col, 10, 9, red); dot(r, col, 10, 8, red); dot(r, col, 10, 6, red)
} }
// 6 waiting: 물음표 깜빡임
for c in 0..<counts[6] { drawBody(row: 6, col: c, dy: 0) { r, col in
    guard c % 3 != 2 else { return }
    for (x, y) in [(9, 11), (10, 12), (11, 11), (11, 10), (10, 9), (10, 7)] { dot(r, col, x, y, dark) }
} }
// 7 running: 제자리 달리기
for c in 0..<counts[7] { drawBody(row: 7, col: c, dy: c % 2, lean: [0, 0, 1, 1, 0, -1][c] * 0) }
// 8 review: 체크 표시
for c in 0..<counts[8] { drawBody(row: 8, col: c, dy: 0, eyes: c % 2 == 0 ? "open" : "closed") { r, col in
    for (x, y) in [(8, 9), (9, 8), (10, 9), (11, 10), (11, 11)] { dot(r, col, x, y, green) }
} }

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
