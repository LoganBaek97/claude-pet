import Foundation

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

    private let framesByRow: [SpriteRow: [SpriteFrame]]

    public init(contentsOf url: URL, spriteVersion: Int = 1,
                decoder: SpriteDecoder.Type = SpriteDecoders.default) throws {
        let atlas = try decoder.decode(contentsOf: url)
        try self.init(atlas: atlas, spriteVersion: spriteVersion)
    }

    public init(atlas: SpriteFrame, spriteVersion: Int = 1) throws {
        guard let height = Self.atlasHeight(forSpriteVersion: spriteVersion) else {
            throw SpriteSheetError.unsupportedSpriteVersion(spriteVersion)
        }
        guard atlas.width == Self.atlasWidth, atlas.height == height else {
            throw SpriteSheetError.wrongSize(width: atlas.width, height: atlas.height)
        }
        var result: [SpriteRow: [SpriteFrame]] = [:]
        for row in SpriteRow.allCases {
            var frames: [SpriteFrame] = []
            for col in 0..<Self.columns {
                let cell = atlas.cropping(x: col * Self.cellWidth, y: row.rawValue * Self.cellHeight,
                                          width: Self.cellWidth, height: Self.cellHeight)
                if cell.isTransparent { break } // 첫 빈 셀에서 행 종료
                frames.append(cell)
            }
            if frames.isEmpty {
                let first = atlas.cropping(x: 0, y: row.rawValue * Self.cellHeight,
                                           width: Self.cellWidth, height: Self.cellHeight)
                frames = [first]
            }
            result[row] = frames
        }
        framesByRow = result
    }

    public func frames(for row: SpriteRow) -> [SpriteFrame] { framesByRow[row] ?? [] }
    public func frameCount(for row: SpriteRow) -> Int { frames(for: row).count }
}

#if canImport(ImageIO)
import CoreGraphics

public extension SpriteSheet {
    /// 기존 코드·테스트와의 호환을 위해 남겨 둔다. CGImage 를 SpriteFrame 으로 변환해 init(atlas:) 에 위임한다.
    init(image: CGImage, spriteVersion: Int = 1) throws {
        try self.init(atlas: SpriteFrame(cgImage: image), spriteVersion: spriteVersion)
    }
}
#endif
