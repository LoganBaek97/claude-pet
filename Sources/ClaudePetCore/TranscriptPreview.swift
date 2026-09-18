import Foundation

/// 세션 트랜스크립트에서 마지막 어시스턴트 발화를 뽑아 말풍선 한 줄로 만든다.
///
/// 훅이 글자를 상태 파일에 적지 않는 이유가 있다. 훅은 POSIX sh 이고 JSON 을 `printf` 로 손수
/// 짜기 때문에, 모델이 낸 임의의 글자(제어문자, 따옴표, 줄바꿈)를 끼워 넣으면 파일이 깨진다.
/// 그래서 훅은 경로만 남기고, 파서가 있는 이쪽에서 읽는다.
public enum TranscriptPreview {
    /// 파일 끝에서 이만큼만 읽는다. 트랜스크립트는 수십 MB 까지 커지고 필요한 건 마지막 발화뿐이다.
    public static let tailBytes = 256 * 1024
    /// 말풍선에 넣을 글자 수 상한. 두 줄에 담길 만큼.
    public static let charLimit = 160

    /// 사용자가 읽고 무언가 해야 하는 상태에만 붙인다.
    /// 작업 중인 세션은 마지막 발화가 계속 바뀌어서 글자가 초마다 들썩이며 시선을 밀린다.
    public static func wantsPreview(for state: PetState) -> Bool {
        switch state {
        case .waiting, .review, .failed: return true
        case .running, .idle: return false
        }
    }

    /// JSONL 을 뒤에서부터 훑어 처음 만나는 어시스턴트 글자를 돌려준다.
    /// 꼬리만 읽으면 첫 줄이 중간에서 잘리므로, 파싱 안 되는 줄은 그냥 건너뛴다.
    public static func lastAssistantText(jsonl: String, agent: Agent) -> String? {
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let text = agent == .codex ? codexText(object) : claudeText(object)
            if let text, !text.isEmpty { return text }
        }
        return nil
    }

    /// Claude Code: `{"type":"assistant","message":{"content":[{"type":"text","text":…}]}}`
    /// `isSidechain` 은 서브에이전트 발화다. 부모 세션의 말풍선이 아니므로 뺀다.
    private static func claudeText(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "assistant" else { return nil }
        guard object["isSidechain"] as? Bool != true else { return nil }
        guard let message = object["message"] as? [String: Any] else { return nil }
        if let content = message["content"] as? String { return content }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        return firstText(in: blocks, key: "text") { $0 == "text" }
    }

    /// Codex: `{"type":"response_item","payload":{"type":"message","role":"assistant",
    /// "content":[{"type":"output_text","text":…}]}}`
    private static func codexText(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              payload["role"] as? String == "assistant",
              let blocks = payload["content"] as? [[String: Any]] else { return nil }
        return firstText(in: blocks, key: "text") { $0 == "output_text" || $0 == "text" }
    }

    /// 한 발화 안에는 생각·도구 호출·글자가 섞여 있다. 글자 블록만 본다.
    private static func firstText(in blocks: [[String: Any]], key: String,
                                  isTextBlock: (String) -> Bool) -> String? {
        for block in blocks {
            guard let type = block["type"] as? String, isTextBlock(type) else { continue }
            if let text = block[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    /// 여러 줄 마크다운을 말풍선용 한 줄로 접는다. 빈 글자가 되면 nil.
    public static func condense(_ text: String, limit: Int) -> String? {
        var s = text
        // 줄 앞의 마크다운 표식(제목, 목록, 인용)과 강조·코드 기호를 없앤다. 말풍선에서 읽을 이유가 없다.
        for pattern in [#"(?m)^[ \t]*(#{1,6}|[-*+]|>|\d+\.)[ \t]+"#, #"[*_`~]"#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        guard s.count > limit else { return s }
        return String(s.prefix(limit)) + "…"
    }
}
