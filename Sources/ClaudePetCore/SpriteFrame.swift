import Foundation

/// RGBA8 프리멀티플라이드 알파 픽셀 버퍼. CoreGraphics 없이도 쓸 수 있도록 플랫폼 독립으로 만든다.
public struct SpriteFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// RGBA8, 프리멀티플라이드 알파, 행 우선, 맨 윗줄부터. count == width*height*4
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// 부분 사각형 복사. 전제조건: 사각형이 경계 안에 있어야 한다.
    public func cropping(x: Int, y: Int, width: Int, height: Int) -> SpriteFrame {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let srcOffset = ((y + row) * self.width + x) * 4
            let dstOffset = row * width * 4
            out[dstOffset..<(dstOffset + width * 4)] = pixels[srcOffset..<(srcOffset + width * 4)]
        }
        return SpriteFrame(width: width, height: height, pixels: out)
    }

    /// 알파 바이트가 모두 8 이하이면 true (현재 SpriteSheet.isTransparent 와 같은 규칙).
    public var isTransparent: Bool {
        var i = 3
        while i < pixels.count {
            if pixels[i] > 8 { return false }
            i += 4
        }
        return true
    }
}
