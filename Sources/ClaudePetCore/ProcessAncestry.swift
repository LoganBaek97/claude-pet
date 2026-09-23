import Foundation

// MARK: - Public types (all platforms)

public struct ProcessNode: Equatable, Sendable {
    public let pid: Int32
    public let parentPid: Int32
    public let executablePath: String

    public init(pid: Int32, parentPid: Int32, executablePath: String) {
        self.pid = pid
        self.parentPid = parentPid
        self.executablePath = executablePath
    }
}

/// 자기 자신부터 부모 방향으로 최대 limit 개의 프로세스 체인을 반환한다. 첫 원소는 startPid.
public protocol ProcessAncestry {
    func chain(from startPid: Int32, limit: Int) -> [ProcessNode]
}

// MARK: - Platform implementations

#if os(Windows)
import WinSDK

public struct WindowsProcessAncestry: ProcessAncestry {
    public init() {}

    public func chain(from startPid: Int32, limit: Int) -> [ProcessNode] {
        guard let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0) else {
            return []
        }
        defer { CloseHandle(snapshot) }

        var processMap: [DWORD: (ppid: DWORD, name: String)] = [:]
        var entry = PROCESSENTRY32W()
        entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)

        guard Process32FirstW(snapshot, &entry) else { return [] }
        repeat {
            let name = withUnsafePointer(to: entry.szExeFile) { ptr in
                ptr.withMemoryRebound(to: UInt16.self, capacity: 260) { wptr in
                    String(decodingCString: wptr, as: UTF16.self)
                }
            }
            processMap[entry.th32ProcessID] = (ppid: entry.th32ParentProcessID, name: name)
        } while Process32NextW(snapshot, &entry)

        var result: [ProcessNode] = []
        var pid = DWORD(bitPattern: startPid)

        for _ in 0..<limit {
            guard pid > 1, let info = processMap[pid] else { break }
            let path = queryFullPath(pid: pid) ?? info.name
            result.append(ProcessNode(
                pid: Int32(bitPattern: pid),
                parentPid: Int32(bitPattern: info.ppid),
                executablePath: path
            ))
            guard info.ppid > 1 else { break }
            pid = info.ppid
        }
        return result
    }

    private func queryFullPath(pid: DWORD) -> String? {
        // PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        guard let handle = OpenProcess(0x1000, false, pid) else { return nil }
        defer { CloseHandle(handle) }
        var size = DWORD(260)
        var buffer = [WCHAR](repeating: 0, count: 261)
        guard QueryFullProcessImageNameW(handle, 0, &buffer, &size), size > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            String(decodingCString: ptr.baseAddress!, as: UTF16.self)
        }
    }
}

#elseif os(macOS)
import Darwin

public struct DarwinProcessAncestry: ProcessAncestry {
    public init() {}

    public func chain(from startPid: Int32, limit: Int) -> [ProcessNode] {
        var result: [ProcessNode] = []
        var pid = startPid
        for _ in 0..<limit {
            guard pid > 1 else { break }
            guard let info = procInfo(pid: pid) else { break }
            result.append(ProcessNode(
                pid: pid,
                parentPid: info.ppid,
                executablePath: info.path
            ))
            guard info.ppid > 1 else { break }
            pid = info.ppid
        }
        return result
    }

    private func procInfo(pid: Int32) -> (ppid: Int32, path: String)? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &kinfo, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        let ppid = kinfo.kp_eproc.e_ppid
        let path = execPath(pid: pid) ?? ""
        return (ppid: ppid, path: path)
    }

    private func execPath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
#endif
