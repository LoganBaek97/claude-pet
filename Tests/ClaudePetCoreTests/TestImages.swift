import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImages {
    /// 1536×1872 시트를 만든다. `filledCells[row]` 에 적힌 열 개수만큼 앞에서부터 불투명 사각형을 그린다.
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
}
