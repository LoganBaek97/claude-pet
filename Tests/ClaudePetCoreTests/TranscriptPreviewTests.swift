import XCTest
@testable import ClaudePetCore

final class TranscriptPreviewTests: XCTestCase {
    // MARK: Claude Code 형식

    /// 마지막 어시스턴트 발화의 글자를 가져온다. 도구 호출만 있는 줄은 건너뛴다.
    func testClaudeTakesLastAssistantText() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"안녕"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"첫 답변"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"두 번째 답변"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}
        """
        XCTAssertEqual(TranscriptPreview.lastAssistantText(jsonl: jsonl, agent: .claude), "두 번째 답변")
    }

    /// 한 발화에 생각과 글자가 섞여 있으면 글자만 쓴다.
    func testClaudeSkipsNonTextBlocks() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"속으로"},{"type":"text","text":"겉으로"}]}}
        """
        XCTAssertEqual(TranscriptPreview.lastAssistantText(jsonl: jsonl, agent: .claude), "겉으로")
    }

    /// 서브에이전트(sidechain) 발화는 부모 세션의 말풍선이 아니다.
    func testClaudeIgnoresSidechain() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"부모 답변"}]}}
        {"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"서브에이전트 답변"}]}}
        """
        XCTAssertEqual(TranscriptPreview.lastAssistantText(jsonl: jsonl, agent: .claude), "부모 답변")
    }

    /// content 가 배열이 아니라 문자열로 오는 경우도 있다.
    func testClaudeAcceptsStringContent() {
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":"바로 문자열"}}"#
        XCTAssertEqual(TranscriptPreview.lastAssistantText(jsonl: jsonl, agent: .claude), "바로 문자열")
    }

    /// 꼬리만 읽으면 첫 줄이 중간에서 잘린다. 깨진 줄은 조용히 건너뛴다.
    func testBrokenLinesAreSkipped() {
        let jsonl = """
        e":"assistant","message":{"role":"assis
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"온전한 줄"}]}}
        """
        XCTAssertEqual(TranscriptPreview.lastAssistantText(jsonl: jsonl, agent: .claude), "온전한 줄")
    }

    func testNoAssistantTextGivesNil() {
        XCTAssertNil(TranscriptPreview.lastAssistantText(jsonl: "", agent: .claude))
        XCTAssertNil(TranscriptPreview.lastAssistantText(jsonl: #"{"type":"user","message":{"content":"질문"}}"#, agent: .claude))
    }

    // MARK: Codex 형식

    func testCodexTakesLastAssistantOutputText() {
        let jsonl = """
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"질문"}]}}
        {"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"코덱스 답변"}]}}
        {"type":"event_msg","payload":{"type":"task_started"}}
        """
        XCTAssertEqual(TranscriptPreview.lastAssistantText(jsonl: jsonl, agent: .codex), "코덱스 답변")
    }

    /// 사용자와 developer 발화는 미리보기가 아니다.
    func testCodexIgnoresOtherRoles() {
        let jsonl = """
        {"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"지시문"}]}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"질문"}]}}
        """
        XCTAssertNil(TranscriptPreview.lastAssistantText(jsonl: jsonl, agent: .codex))
    }

    // MARK: 한 줄로 접기

    func testCondenseCollapsesWhitespace() {
        XCTAssertEqual(TranscriptPreview.condense("첫 줄\n\n둘째  줄\t끝", limit: 100), "첫 줄 둘째 줄 끝")
    }

    func testCondenseTrimsAndTruncates() {
        XCTAssertEqual(TranscriptPreview.condense("   앞뒤 공백   ", limit: 100), "앞뒤 공백")
        XCTAssertEqual(TranscriptPreview.condense("abcdefghij", limit: 5), "abcde…")
        XCTAssertEqual(TranscriptPreview.condense("abcde", limit: 5), "abcde")
    }

    /// 마크다운 표식은 말풍선에서 읽을 이유가 없다.
    func testCondenseStripsMarkdownMarkers() {
        XCTAssertEqual(TranscriptPreview.condense("## 제목", limit: 100), "제목")
        XCTAssertEqual(TranscriptPreview.condense("- 목록 항목", limit: 100), "목록 항목")
        XCTAssertEqual(TranscriptPreview.condense("**굵게** 그리고 `코드`", limit: 100), "굵게 그리고 코드")
    }

    /// 밑줄은 강조 기호이기도 하지만 코드 식별자에 훨씬 흔하다. 지우면 글자를 망친다.
    func testCondenseKeepsUnderscores() {
        XCTAssertEqual(TranscriptPreview.condense("file_path 를 고쳤습니다", limit: 100), "file_path 를 고쳤습니다")
    }

    func testCondenseEmptyGivesNil() {
        XCTAssertNil(TranscriptPreview.condense("   \n  ", limit: 100))
        XCTAssertNil(TranscriptPreview.condense("", limit: 100))
    }

    // MARK: 미리보기를 붙일 상태

    /// 사용자가 읽고 뭔가 해야 하는 상태에만 붙인다. 작업 중은 매초 바뀌어 시선을 밀린다.
    func testOnlyActionableStatesWantPreview() {
        XCTAssertTrue(TranscriptPreview.wantsPreview(for: .waiting))
        XCTAssertTrue(TranscriptPreview.wantsPreview(for: .review))
        XCTAssertTrue(TranscriptPreview.wantsPreview(for: .failed))
        XCTAssertFalse(TranscriptPreview.wantsPreview(for: .running))
        XCTAssertFalse(TranscriptPreview.wantsPreview(for: .idle))
    }
}

// MARK: 파일에서 읽기

final class TranscriptStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ lines: String, name: String = "t.jsonl") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try lines.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func summary(_ state: PetState, transcript: String?, agent: Agent = .claude) -> SessionSummary {
        SessionSummary(session: SessionState(sessionId: "s", state: state, cwd: "/p/x",
                                             transcript: transcript, agent: agent, ts: 1), state: state)
    }

    func assistant(_ text: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    func testReadsPreviewFromFile() throws {
        let url = try write(assistant("허락해 주실래요?"))
        let store = TranscriptStore()
        XCTAssertEqual(store.preview(for: summary(.waiting, transcript: url.path)), "허락해 주실래요?")
    }

    /// 미리보기를 붙이지 않는 상태면 파일을 아예 보지 않는다.
    func testSkipsStatesWithoutPreview() throws {
        let url = try write(assistant("작업 중 답변"))
        let store = TranscriptStore()
        XCTAssertNil(store.preview(for: summary(.running, transcript: url.path)))
        XCTAssertNil(store.preview(for: summary(.idle, transcript: url.path)))
    }

    func testMissingOrEmptyPathGivesNil() {
        let store = TranscriptStore()
        XCTAssertNil(store.preview(for: summary(.review, transcript: nil)))
        XCTAssertNil(store.preview(for: summary(.review, transcript: "")))
        XCTAssertNil(store.preview(for: summary(.review, transcript: dir.appendingPathComponent("없음.jsonl").path)))
    }

    /// 파일이 자라면 새로 읽는다.
    func testRereadsWhenFileGrows() throws {
        let url = try write(assistant("첫 답변"))
        let store = TranscriptStore()
        XCTAssertEqual(store.preview(for: summary(.review, transcript: url.path)), "첫 답변")
        try (assistant("첫 답변") + "\n" + assistant("새 답변") + "\n").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.preview(for: summary(.review, transcript: url.path)), "새 답변")
    }

    /// 꼬리만 읽어도 마지막 발화는 잡힌다. 앞쪽 잘린 줄은 버린다.
    func testReadsOnlyTailButStillFindsLast() throws {
        let filler = (0..<400).map { assistant("채우기 \($0) " + String(repeating: "가", count: 200)) }.joined(separator: "\n")
        let url = try write(filler + "\n" + assistant("맨 끝 답변") + "\n")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, TranscriptPreview.tailBytes, "꼬리 읽기가 실제로 동작하는 크기여야 한다")
        let store = TranscriptStore()
        XCTAssertEqual(store.preview(for: summary(.review, transcript: url.path)), "맨 끝 답변")
    }

    /// 꼬리를 자르면 첫 줄이 글자 중간에서 끊긴다. 그 줄만 버리고 뒤의 온전한 발화는 살려야 한다.
    /// 실제로 자른 모양을 그대로 본뜬다. 깨진 바이트로 시작하는 반 토막 줄, 줄바꿈, 온전한 줄.
    func testBrokenUTF8TailStillYieldsLastMessage() throws {
        let url = dir.appendingPathComponent("broken.jsonl")
        var data = Data([0xED, 0x95])   // "한" 의 앞 두 바이트만. 홀로는 올바른 UTF-8 이 아니다.
        data.append(Data(#"ssistant","content":[{"type":"text","text":"반 토막"}]}}"#.utf8))
        data.append(Data("\n".utf8))
        data.append(Data((assistant("온전한 마지막 답변") + "\n").utf8))
        try data.write(to: url)
        let store = TranscriptStore()
        XCTAssertEqual(store.preview(for: summary(.review, transcript: url.path)), "온전한 마지막 답변")
    }

    func testForgetAllDropsSessionsThatAreGone() throws {
        let url = try write(assistant("답변"))
        let store = TranscriptStore()
        XCTAssertEqual(store.preview(for: summary(.review, transcript: url.path)), "답변")
        store.forgetAll(except: [])
        // 캐시를 버려도 파일이 있으면 다시 읽어 같은 값을 준다.
        XCTAssertEqual(store.preview(for: summary(.review, transcript: url.path)), "답변")
    }
}
