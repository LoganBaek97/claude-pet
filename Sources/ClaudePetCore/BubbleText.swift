import Foundation

public enum BubbleText {
    public static func text(for agg: Aggregate) -> String? {
        guard let s = agg.session else { return nil }
        let project = s.projectName
        func join(_ a: String, _ b: String) -> String {
            [a, b].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        switch agg.state {
        case .idle:
            return nil
        case .running:
            return s.tool.isEmpty ? join("작업 중", project) : join(s.tool, project)
        case .waiting:
            let base = join("입력 대기", project)
            return agg.waitingCount > 1 ? "\(base) +\(agg.waitingCount - 1)" : base
        case .failed:
            return join("실패", s.tool.isEmpty ? project : s.tool)
        case .review:
            return join("끝남", project)
        }
    }

    public static func isEmphasized(_ state: PetState) -> Bool {
        state == .waiting || state == .failed
    }
}
