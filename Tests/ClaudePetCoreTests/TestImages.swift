import Foundation
@testable import ClaudePetCore

#if canImport(ImageIO)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

enum TestImages {
    /// 1536×1872 SpriteFrame 을 만든다. `filledCells[row]` 에 적힌 열 개수만큼 앞에서부터
    /// 100×100 빨간 사각형을 각 셀 (col*192+40, row*208+40) 에 그린다. 위 행이 메모리 앞.
    static func sheetFrame(filledCells: [Int], width: Int = 1536, height: Int = 1872) -> SpriteFrame {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (row, count) in filledCells.enumerated() {
            for col in 0..<count {
                let rectX = col * 192 + 40
                let rectY = row * 208 + 40
                for py in rectY..<(rectY + 100) {
                    for px in rectX..<(rectX + 100) {
                        let offset = (py * width + px) * 4
                        pixels[offset]     = 255 // R
                        pixels[offset + 1] = 0   // G
                        pixels[offset + 2] = 0   // B
                        pixels[offset + 3] = 255 // A
                    }
                }
            }
        }
        return SpriteFrame(width: width, height: height, pixels: pixels)
    }

#if canImport(ImageIO)
    /// CGImage 기반 시트 픽스처. CGContext 원점은 좌하단이므로 y 를 뒤집는다.
    static func sheet(filledCells: [Int], width: Int = 1536, height: Int = 1872) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        for (row, count) in filledCells.enumerated() {
            for col in 0..<count {
                // CGContext 원점은 좌하단. 행 0 이 이미지 맨 위가 되도록 뒤집는다.
                let y = height - (row + 1) * 208 + 40
                ctx.fill(CGRect(x: col * 192 + 40, y: y, width: 100, height: 100))
            }
        }
        return ctx.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
#endif
}
