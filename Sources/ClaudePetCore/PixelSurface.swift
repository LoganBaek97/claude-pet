import Foundation

/// BGRA 프리멀티플라이드 알파 픽셀 버퍼. Windows 에서 DIB 로 올리기 전에 펫과 말풍선을 합성하는 곳이다.
/// Win32 의존성이 없어 macOS 에서도 컴파일하고 테스트할 수 있다.
public struct PixelSurface: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// BGRA8, 프리멀티플라이드 알파, 행 우선, 맨 윗줄부터(top-down). count == width * height * 4.
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    public mutating func clear() {
        for i in pixels.indices { pixels[i] = 0 }
    }

    // MARK: - SpriteFrame 그리기

    /// SpriteFrame (RGBA premultiplied) 을 BGRA 로 교환하면서 최근접 보간으로 그린다.
    public mutating func blitSpriteFrame(_ frame: SpriteFrame, dstX: Int, dstY: Int, dstW: Int, dstH: Int) {
        let sw = frame.width, sh = frame.height
        guard sw > 0, sh > 0, dstW > 0, dstH > 0 else { return }
        for py in 0..<dstH {
            let screenY = dstY + py
            guard screenY >= 0, screenY < height else { continue }
            let sy = py * sh / dstH
            let srcRow = sy * sw * 4
            for px in 0..<dstW {
                let screenX = dstX + px
                guard screenX >= 0, screenX < width else { continue }
                let sx = px * sw / dstW
                let si = srcRow + sx * 4
                let a = frame.pixels[si + 3]
                guard a > 0 else { continue }
                let di = (screenY * width + screenX) * 4
                // RGBA -> BGRA: source-over composite
                let invA = UInt16(255 - a)
                pixels[di + 0] = UInt8(min(255, UInt16(frame.pixels[si + 2]) + UInt16(pixels[di + 0]) * invA / 255))
                pixels[di + 1] = UInt8(min(255, UInt16(frame.pixels[si + 1]) + UInt16(pixels[di + 1]) * invA / 255))
                pixels[di + 2] = UInt8(min(255, UInt16(frame.pixels[si + 0]) + UInt16(pixels[di + 2]) * invA / 255))
                pixels[di + 3] = UInt8(min(255, UInt16(a) + UInt16(pixels[di + 3]) * invA / 255))
            }
        }
    }

    // MARK: - 버퍼 합성

    /// source-over 합성. src 와 dst 모두 BGRA 프리멀티플라이드.
    public mutating func compositeOver(_ src: PixelSurface, dstX: Int, dstY: Int) {
        for sy in 0..<src.height {
            let screenY = dstY + sy
            guard screenY >= 0, screenY < height else { continue }
            for sx in 0..<src.width {
                let screenX = dstX + sx
                guard screenX >= 0, screenX < width else { continue }
                let si = (sy * src.width + sx) * 4
                let sa = UInt16(src.pixels[si + 3])
                guard sa > 0 else { continue }
                let di = (screenY * width + screenX) * 4
                let invSa = 255 - sa
                pixels[di + 0] = UInt8(min(255, UInt16(src.pixels[si + 0]) + UInt16(pixels[di + 0]) * invSa / 255))
                pixels[di + 1] = UInt8(min(255, UInt16(src.pixels[si + 1]) + UInt16(pixels[di + 1]) * invSa / 255))
                pixels[di + 2] = UInt8(min(255, UInt16(src.pixels[si + 2]) + UInt16(pixels[di + 2]) * invSa / 255))
                pixels[di + 3] = UInt8(min(255, sa + UInt16(pixels[di + 3]) * invSa / 255))
            }
        }
    }

    // MARK: - 도형

    /// 프리멀티플라이드 BGRA 로 둥근 직사각형을 채운다. 입력은 직선(non-premultiplied) RGBA.
    public mutating func fillRoundedRect(x: Int, y: Int, w: Int, h: Int, radius: Int,
                                         r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard a > 0 else { return }
        let pa = UInt16(a)
        // premultiply
        let pb = UInt8(UInt16(b) * pa / 255)
        let pg = UInt8(UInt16(g) * pa / 255)
        let pr = UInt8(UInt16(r) * pa / 255)
        let rad = min(radius, min(w, h) / 2)
        let invA = 255 - pa

        for py in 0..<h {
            let screenY = y + py
            guard screenY >= 0, screenY < height else { continue }
            for px in 0..<w {
                let screenX = x + px
                guard screenX >= 0, screenX < width else { continue }
                if !Self.inRoundedRect(px: px, py: py, w: w, h: h, rad: rad) { continue }
                let di = (screenY * width + screenX) * 4
                pixels[di + 0] = UInt8(min(255, UInt16(pb) + UInt16(pixels[di + 0]) * invA / 255))
                pixels[di + 1] = UInt8(min(255, UInt16(pg) + UInt16(pixels[di + 1]) * invA / 255))
                pixels[di + 2] = UInt8(min(255, UInt16(pr) + UInt16(pixels[di + 2]) * invA / 255))
                pixels[di + 3] = UInt8(min(255, pa + UInt16(pixels[di + 3]) * invA / 255))
            }
        }
    }

    /// 불투명 직사각형. 이미 있는 픽셀을 덮어쓴다.
    public mutating func fillRect(x: Int, y: Int, w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        for py in 0..<h {
            let screenY = y + py
            guard screenY >= 0, screenY < height else { continue }
            for px in 0..<w {
                let screenX = x + px
                guard screenX >= 0, screenX < width else { continue }
                let di = (screenY * width + screenX) * 4
                let pa = UInt16(a)
                pixels[di + 0] = UInt8(UInt16(b) * pa / 255)  // B
                pixels[di + 1] = UInt8(UInt16(g) * pa / 255)  // G
                pixels[di + 2] = UInt8(UInt16(r) * pa / 255)  // R
                pixels[di + 3] = a
            }
        }
    }

    private static func inRoundedRect(px: Int, py: Int, w: Int, h: Int, rad: Int) -> Bool {
        let cornerX: Int
        let cornerY: Int
        if px < rad && py < rad {
            cornerX = rad; cornerY = rad
        } else if px >= w - rad && py < rad {
            cornerX = w - rad - 1; cornerY = rad
        } else if px < rad && py >= h - rad {
            cornerX = rad; cornerY = h - rad - 1
        } else if px >= w - rad && py >= h - rad {
            cornerX = w - rad - 1; cornerY = h - rad - 1
        } else {
            return true
        }
        let dx = px - cornerX
        let dy = py - cornerY
        return dx * dx + dy * dy <= rad * rad
    }

    // MARK: - 조회

    /// 특정 좌표의 알파값.
    public func alpha(atX x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return pixels[(y * width + x) * 4 + 3]
    }

    /// 버퍼에 알파가 0이 아닌 픽셀이 하나라도 있는지.
    public var hasVisiblePixels: Bool {
        var i = 3
        while i < pixels.count {
            if pixels[i] > 0 { return true }
            i += 4
        }
        return false
    }
}
