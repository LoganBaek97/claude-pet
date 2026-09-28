import XCTest
@testable import ClaudePetCore

#if canImport(ImageIO)
import CoreGraphics
#endif

final class SpriteSheetTests: XCTestCase {
    func testRowOrderAndNominalCounts() {
        XCTAssertEqual(SpriteRow.allCases.map(\.rawValue), Array(0...8))
        XCTAssertEqual(SpriteRow.allCases.map(\.nominalFrameCount), [6, 8, 8, 4, 5, 8, 6, 6, 6])
        XCTAssertEqual(SpriteRow.base(for: .idle), .idle)
        XCTAssertEqual(SpriteRow.base(for: .running), .running)
        XCTAssertEqual(SpriteRow.base(for: .waiting), .waiting)
        XCTAssertEqual(SpriteRow.base(for: .failed), .failed)
        XCTAssertEqual(SpriteRow.base(for: .review), .review)
    }

    func testRejectsWrongSize() {
        let small = TestImages.sheetFrame(filledCells: [], width: 100, height: 100)
        XCTAssertThrowsError(try SpriteSheet(atlas: small)) { error in
            XCTAssertEqual(error as? SpriteSheetError, .wrongSize(width: 100, height: 100))
        }
    }

    func testAcceptsV2SheetWhenDeclared() throws {
        let frame = TestImages.sheetFrame(filledCells: [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8], height: 2288)
        let sheet = try SpriteSheet(atlas: frame, spriteVersion: 2)
        XCTAssertEqual(SpriteRow.allCases.map { sheet.frameCount(for: $0) }, [6, 8, 8, 4, 5, 8, 6, 6, 6])
    }

    /// 계약: spriteVersionNumber 를 생략(v1)한 펫이 2288 시트를 들고 오면 거부한다. 반대 조합도 거부한다.
    func testRejectsHeightMismatchingDeclaredVersion() {
        let v2 = TestImages.sheetFrame(filledCells: [], height: 2288)
        XCTAssertThrowsError(try SpriteSheet(atlas: v2)) { error in
            XCTAssertEqual(error as? SpriteSheetError, .wrongSize(width: 1536, height: 2288))
        }
        let v1 = TestImages.sheetFrame(filledCells: [])
        XCTAssertThrowsError(try SpriteSheet(atlas: v1, spriteVersion: 2)) { error in
            XCTAssertEqual(error as? SpriteSheetError, .wrongSize(width: 1536, height: 1872))
        }
    }

    func testRejectsUnknownSpriteVersion() {
        let v1 = TestImages.sheetFrame(filledCells: [])
        XCTAssertThrowsError(try SpriteSheet(atlas: v1, spriteVersion: 3)) { error in
            XCTAssertEqual(error as? SpriteSheetError, .unsupportedSpriteVersion(3))
        }
        XCTAssertNil(SpriteSheet.atlasHeight(forSpriteVersion: 0))
        XCTAssertEqual(SpriteSheet.atlasHeight(forSpriteVersion: 1), 1872)
        XCTAssertEqual(SpriteSheet.atlasHeight(forSpriteVersion: 2), 2288)
    }

    func testCutsFramesAndDropsTransparentCells() throws {
        let frame = TestImages.sheetFrame(filledCells: [6, 8, 8, 4, 5, 8, 6, 6, 6])
        let sheet = try SpriteSheet(atlas: frame)
        XCTAssertEqual(SpriteRow.allCases.map { sheet.frameCount(for: $0) }, [6, 8, 8, 4, 5, 8, 6, 6, 6])
        let cell = sheet.frames(for: .idle)[0]
        XCTAssertEqual(cell.width, 192)
        XCTAssertEqual(cell.height, 208)
    }

    func testRowWithFewerFramesThanNominal() throws {
        let frame = TestImages.sheetFrame(filledCells: [3, 8, 8, 4, 5, 8, 6, 6, 6])
        let sheet = try SpriteSheet(atlas: frame)
        XCTAssertEqual(sheet.frameCount(for: .idle), 3)
    }

    func testEmptyRowFallsBackToNominalCells() throws {
        // 행이 통째로 비어 있으면(잘못 만든 시트) 최소한 첫 셀 하나는 돌려줘 앱이 죽지 않게 한다.
        let frame = TestImages.sheetFrame(filledCells: [0, 8, 8, 4, 5, 8, 6, 6, 6])
        let sheet = try SpriteSheet(atlas: frame)
        XCTAssertEqual(sheet.frameCount(for: .idle), 1)
    }

#if canImport(ImageIO)
    func testLoadsFromFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        TestImages.writePNG(TestImages.sheet(filledCells: [6, 8, 8, 4, 5, 8, 6, 6, 6]), to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let sheet = try SpriteSheet(contentsOf: url)
        XCTAssertEqual(sheet.frameCount(for: .waving), 4)
    }

    /// CGImage 경로와 순수 픽셀 경로가 같은 프레임 수를 생성하는지 확인한다.
    /// 두 픽스처 경로가 일치해야 맥 렌더링이 보호된다.
    func testSpriteFrameMatchesCGImagePath() throws {
        let cgImage = TestImages.sheet(filledCells: [6, 8, 8, 4, 5, 8, 6, 6, 6])
        let sheetFromCG = try SpriteSheet(image: cgImage)
        let sheetFromPure = try SpriteSheet(atlas: TestImages.sheetFrame(filledCells: [6, 8, 8, 4, 5, 8, 6, 6, 6]))
        XCTAssertEqual(
            SpriteRow.allCases.map { sheetFromCG.frameCount(for: $0) },
            SpriteRow.allCases.map { sheetFromPure.frameCount(for: $0) }
        )
    }
#endif

    func testMissingFileThrowsCannotDecode() {
        XCTAssertThrowsError(try SpriteSheet(contentsOf: URL(fileURLWithPath: "/nonexistent.webp"))) { error in
            XCTAssertEqual(error as? SpriteSheetError, .cannotDecode)
        }
    }

    func testDefaultPetSheetHasExpectedFrameCounts() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Resources/pets/default/spritesheet.png")
        let sheet = try SpriteSheet(contentsOf: url)
        XCTAssertEqual(SpriteRow.allCases.map { sheet.frameCount(for: $0) }, [6, 8, 8, 4, 5, 8, 6, 6, 6])
    }
}
