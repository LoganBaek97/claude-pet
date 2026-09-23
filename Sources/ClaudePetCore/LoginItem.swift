import Foundation
#if os(Windows)
import WinSDK
#endif

/// 로그인 시 자동 실행. macOS 는 SMAppService(앱 레이어에서), Windows 는 HKCU Run 키.
public enum LoginItem {
    public static let windowsValueName = "ClaudePet"
    static let runKeyPath = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"

    #if os(Windows)
    private static func openRunKey(write: Bool) -> HKEY? {
        var key: HKEY?
        let access = REGSAM(write ? KEY_SET_VALUE | KEY_QUERY_VALUE : KEY_QUERY_VALUE)
        let status = runKeyPath.withCString(encodedAs: UTF16.self) { path in
            RegCreateKeyExW(HKEY_CURRENT_USER, path, 0, nil, DWORD(REG_OPTION_NON_VOLATILE), access, nil, &key, nil)
        }
        return status == ERROR_SUCCESS ? key : nil
    }

    /// `"C:\…\ClaudePetWin.exe"` 를 Run 키에 등록한다.
    public static func enable(appExecutable: URL) throws {
        guard let key = openRunKey(write: true) else { throw LoginItemError.registry }
        defer { RegCloseKey(key) }
        let value = "\"\(appExecutable.path.replacingOccurrences(of: "/", with: "\\"))\""
        let utf16 = Array(value.utf16) + [0]
        let status = windowsValueName.withCString(encodedAs: UTF16.self) { name in
            utf16.withUnsafeBufferPointer { buf in
                RegSetValueExW(key, name, 0, DWORD(REG_SZ), UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: BYTE.self),
                               DWORD(buf.count * MemoryLayout<UInt16>.size))
            }
        }
        guard status == ERROR_SUCCESS else { throw LoginItemError.registry }
    }

    public static func disable() throws {
        guard let key = openRunKey(write: true) else { throw LoginItemError.registry }
        defer { RegCloseKey(key) }
        let status = windowsValueName.withCString(encodedAs: UTF16.self) { RegDeleteValueW(key, $0) }
        guard status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND else { throw LoginItemError.registry }
    }

    public static var isEnabled: Bool {
        guard let key = openRunKey(write: false) else { return false }
        defer { RegCloseKey(key) }
        let status = windowsValueName.withCString(encodedAs: UTF16.self) { RegQueryValueExW(key, $0, nil, nil, nil, nil) }
        return status == ERROR_SUCCESS
    }
    #endif

    public enum LoginItemError: Error { case registry }
}
