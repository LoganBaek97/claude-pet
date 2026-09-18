import Foundation

/// 트랜스크립트 파일에서 미리보기를 읽어 두는 곳. 파일이 자란 것만 다시 읽는다.
///
/// 말풍선은 경과 시간 때문에 1초마다 글자를 새로 쓴다. 그때마다 수십 MB 파일을 여는 대신
/// (경로, 크기, 수정 시각)이 그대로면 지난 값을 그대로 준다.
/// 메인 스레드에서만 쓴다.
public final class TranscriptStore {
    private struct Key: Equatable {
        let path: String
        let size: Int
        let modified: TimeInterval
    }

    private struct Entry {
        let key: Key
        let preview: String?
    }

    private let tailBytes: Int
    private let charLimit: Int
    private var entries: [String: Entry] = [:]

    public init(tailBytes: Int = TranscriptPreview.tailBytes, charLimit: Int = TranscriptPreview.charLimit) {
        self.tailBytes = tailBytes
        self.charLimit = charLimit
    }

    /// 그 세션의 마지막 답변 한 줄. 미리보기를 붙이지 않는 상태거나 읽을 수 없으면 nil.
    public func preview(for summary: SessionSummary) -> String? {
        guard TranscriptPreview.wantsPreview(for: summary.state) else { return nil }
        guard let path = summary.session.transcript, !path.isEmpty else { return nil }
        guard let key = key(for: path) else { return nil }
        if let cached = entries[path], cached.key == key { return cached.preview }
        let preview = read(path: path, agent: summary.session.agent)
        entries[path] = Entry(key: key, preview: preview)
        return preview
    }

    /// 살아 있지 않은 세션의 것은 버린다. 세션이 오래 도는 기계에서 캐시가 무한정 자라지 않게.
    public func forgetAll(except live: Set<String>) {
        entries = entries.filter { live.contains($0.key) }
    }

    private func key(for path: String) -> Key? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int,
              let modified = attrs[.modificationDate] as? Date else { return nil }
        return Key(path: path, size: size, modified: modified.timeIntervalSince1970)
    }

    /// 파일 끝에서 `tailBytes` 만큼만 읽는다. 앞이 잘려 첫 줄이 깨지는 건 파서가 건너뛴다.
    private func read(path: String, agent: Agent) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            let offset = end > UInt64(tailBytes) ? end - UInt64(tailBytes) : 0
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd() else { return nil }
            // 꼬리를 자르면 UTF-8 글자 중간에서 끊긴다. 손실을 허용해 디코딩하면 깨진 자리만
            // 대체 문자가 되고 나머지 줄은 그대로 읽힌다. 엄격하게 하면 파일 전체를 버리게 된다.
            let text = String(decoding: data, as: UTF8.self)
            guard let raw = TranscriptPreview.lastAssistantText(jsonl: text, agent: agent) else { return nil }
            return TranscriptPreview.condense(raw, limit: charLimit)
        } catch {
            return nil
        }
    }

}
