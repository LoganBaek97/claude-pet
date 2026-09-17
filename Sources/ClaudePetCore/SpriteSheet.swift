import CoreGraphics
import Foundation
import ImageIO

public enum SpriteSheetError: Error, Equatable {
    case cannotDecode
    case wrongSize(width: Int, height: Int)
    case unsupportedSpriteVersion(Int)
}

/// Codex 펫 시트. v1 은 8열×9행(1536×1872), v2 는 뒤에 look 두 행이 붙은 8열×11행(1536×2288).
/// 행 0~8 은 두 버전이 같다. 버전은 매니페스트 `spriteVersionNumber` 로 정하고, 시트 높이는 그 선언과 맞아야 한다.
public struct SpriteSheet {
    public static let atlasWidth = 1536
    public static let columns = 8
    public static let cellWidth = 192
    public static let cellHeight = 208

    /// 선언된 버전에 맞는 행 수. 계약에 없는 버전이면 nil.
    public static func rows(forSpriteVersion version: Int) -> Int? {
        switch version {
        case 1: return 9
        case 2: return 11
        default: return nil
        }
    }

    public static func atlasHeight(forSpriteVersion version: Int) -> Int? {
        rows(forSpriteVersion: version).map { $0 * cellHeight }
    }

    private let framesByRow: [SpriteRow: [CGImage]]

    public init(contentsOf url: URL, spriteVersion: Int = 1) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SpriteSheetError.cannotDecode
        }
        try self.init(image: image, spriteVersion: spriteVersion)
    }

    public init(image: CGImage, spriteVersion: Int = 1) throws {
        guard let height = Self.atlasHeight(forSpriteVersion: spriteVersion) else {
            throw SpriteSheetError.unsupportedSpriteVersion(spriteVersion)
        }
        guard image.width == Self.atlasWidth, image.height == height else {
            throw SpriteSheetError.wrongSize(width: image.width, height: image.height)
        }
        var result: [SpriteRow: [CGImage]] = [:]
        for row in SpriteRow.allCases {
            var frames: [CGImage] = []
            for col in 0..<Self.columns {
                let rect = CGRect(x: col * Self.cellWidth, y: row.rawValue * Self.cellHeight,
                                  width: Self.cellWidth, height: Self.cellHeight)
                guard let cell = image.cropping(to: rect) else { continue }
                if Self.isTransparent(cell) { break } // 첫 빈 셀에서 행 종료
                frames.append(cell)
            }
            if frames.isEmpty, let first = image.cropping(to: CGRect(x: 0, y: row.rawValue * Self.cellHeight,
                                                                      width: Self.cellWidth, height: Self.cellHeight)) {
                frames = [first]
            }
            result[row] = frames
        }
        framesByRow = result
    }

    public func frames(for row: SpriteRow) -> [CGImage] { framesByRow[row] ?? [] }
    public func frameCount(for row: SpriteRow) -> Int { frames(for: row).count }

    /// 셀 원본 크기(192×208) 비트맵에 그린 뒤 알파가 전부 0 인지 본다. 로드 시 한 번뿐이므로 비용은 무시할 만하다(F-6).
    static func isTransparent(_ cell: CGImage) -> Bool {
        let w = cellWidth, h = cellHeight
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .none
        ctx.draw(cell, in: CGRect(x: 0, y: 0, width: w, height: h))
        var i = 3
        while i < pixels.count {
            if pixels[i] > 8 { return false }
            i += 4
        }
        return true
    }
}
