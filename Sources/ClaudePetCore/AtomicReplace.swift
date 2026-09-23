import Foundation
#if os(Windows)
import WinSDK
#endif

extension FileManager {
    /// `source` 를 `target` 자리에 놓는다. 이미 있으면 바꾼다.
    /// Windows 의 corelibs Foundation 은 `replaceItemAt` 을 구현하지 않아("not yet implemented")
    /// 파일은 `MoveFileExW(REPLACE_EXISTING)` 으로, 디렉터리는 지우고 옮기는 식으로 처리한다.
    /// macOS 는 `replaceItemAt` 을 그대로 쓴다.
    func replaceItemAtomically(_ target: URL, with source: URL) throws {
        var isDir: ObjCBool = false
        let targetExists = fileExists(atPath: target.path, isDirectory: &isDir)
        guard targetExists else {
            try moveItem(at: source, to: target)
            return
        }
        #if os(Windows)
        if isDir.boolValue {
            try removeItem(at: target)
            try moveItem(at: source, to: target)
            return
        }
        let ok = source.path.withCString(encodedAs: UTF16.self) { src in
            target.path.withCString(encodedAs: UTF16.self) { dst in
                MoveFileExW(src, dst, DWORD(MOVEFILE_REPLACE_EXISTING) | DWORD(MOVEFILE_WRITE_THROUGH))
            }
        }
        if !ok {
            // Defender 가 잠깐 잡고 있을 수 있다. 한 번 더.
            Thread.sleep(forTimeInterval: 0.1)
            try? removeItem(at: target)
            try moveItem(at: source, to: target)
        }
        #else
        _ = try replaceItemAt(target, withItemAt: source)
        #endif
    }
}
