import Foundation

public protocol SpriteDecoder {
    static func decode(contentsOf url: URL) throws -> SpriteFrame
}

public enum SpriteDecoders {
    #if canImport(ImageIO)
    public static var `default`: SpriteDecoder.Type = ImageIODecoder.self
    #else
    public static var `default`: SpriteDecoder.Type = UnavailableDecoder.self
    #endif
}

#if !canImport(ImageIO)
public enum UnavailableDecoder: SpriteDecoder {
    public static func decode(contentsOf url: URL) throws -> SpriteFrame {
        throw SpriteSheetError.cannotDecode
    }
}
#endif

#if canImport(ImageIO)
import CoreGraphics
import ImageIO

public enum ImageIODecoder: SpriteDecoder {
    public static func decode(contentsOf url: URL) throws -> SpriteFrame {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SpriteSheetError.cannotDecode
        }
        return SpriteFrame(cgImage: image)
    }
}

public extension SpriteFrame {
    /// CGImage 를 RGBA8 프리멀티플라이드 알파 버퍼로 렌더해 SpriteFrame 을 만든다.
    init(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            self.init(width: w, height: h, pixels: buf)
            return
        }
        ctx.interpolationQuality = .none
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.init(width: w, height: h, pixels: buf)
    }
}
#endif
