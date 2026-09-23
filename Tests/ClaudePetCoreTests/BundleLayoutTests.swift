import XCTest
@testable import ClaudePetCore

final class BundleLayoutTests: XCTestCase {
#if os(macOS)
    func testInsideAppBundle() {
        let exe = URL(fileURLWithPath: "/Applications/ClaudePet.app/Contents/MacOS/ClaudePetApp")
        XCTAssertEqual(BundleLayout.appBundle(containing: exe)?.path, "/Applications/ClaudePet.app")
        XCTAssertEqual(BundleLayout.hookScript(executable: exe).path, "/Applications/ClaudePet.app/Contents/Resources/hook.sh")
        XCTAssertEqual(BundleLayout.builtinPetDirectory(executable: exe).path, "/Applications/ClaudePet.app/Contents/Resources/pets/default")
    }

    func testCliInsideAppBundleResolvesSameResources() {
        let exe = URL(fileURLWithPath: "/Applications/ClaudePet.app/Contents/MacOS/claude-pet")
        XCTAssertEqual(BundleLayout.hookScript(executable: exe).path, "/Applications/ClaudePet.app/Contents/Resources/hook.sh")
    }

    func testDevelopmentBuildFallsBackToRepoLayout() {
        let exe = URL(fileURLWithPath: "/Users/x/claude-pet/.build/debug/ClaudePetApp")
        XCTAssertNil(BundleLayout.appBundle(containing: exe))
        XCTAssertEqual(BundleLayout.hookScript(executable: exe).path, "/Users/x/claude-pet/hooks/hook.sh")
        XCTAssertEqual(BundleLayout.builtinPetDirectory(executable: exe).path, "/Users/x/claude-pet/Resources/pets/default")

        // SwiftPM 은 .build/debug 를 .build/<triple>/debug 심링크로 만든다. 심링크를 따라가면 안 된다.
        let fm = FileManager.default
        let repo = fm.temporaryDirectory.appendingPathComponent("bundle-layout-\(UUID().uuidString)", isDirectory: true)
        let real = repo.appendingPathComponent(".build/arm64-apple-macosx/debug", isDirectory: true)
        try! fm.createDirectory(at: real, withIntermediateDirectories: true)
        try! fm.createSymbolicLink(at: repo.appendingPathComponent(".build/debug"), withDestinationURL: real)
        defer { try? fm.removeItem(at: repo) }
        let linked = repo.appendingPathComponent(".build/debug/ClaudePetApp")
        XCTAssertEqual(BundleLayout.hookScript(executable: linked).path,
                       repo.appendingPathComponent("hooks/hook.sh").path)
    }
#endif

    /// Windows 배포 레이아웃: 같은 디렉터리에 claude-pet.exe 를 둔다.
    /// 이 테스트는 순수 문자열 연산이라 모든 플랫폼에서 돈다.
    func testHookExecutable() {
        let exe = URL(fileURLWithPath: "/x/y/claude-pet")
        XCTAssertEqual(BundleLayout.hookExecutable(executable: exe).path, "/x/y/claude-pet.exe")
    }
}
