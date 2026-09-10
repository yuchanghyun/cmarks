import Foundation

/// 빠른 열기용 부분 순서 매칭. 질문의 모든 글자가 순서대로 나오면 매치. 점수가 높을수록 좋다.
/// 가산점: 연속 매치, 경로 구분자·단어 시작 매치, 파일 이름 안 매치. 감점: 매치 사이 간격.
public enum FuzzyMatcher {
    public struct Match: Sendable, Equatable {
        public var score: Int
        /// 매치된 위치(표시용 강조).
        public var positions: [Int]
    }

    public static func match(_ query: String, in candidate: String, fileNameStart: Int? = nil) -> Match? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return Match(score: 0, positions: []) }
        let c = Array(candidate.lowercased())
        let original = Array(candidate)
        guard c.count >= q.count else { return nil }

        var positions: [Int] = []
        var score = 0
        var ci = 0
        var lastMatch = -2
        for qc in q {
            var found = -1
            while ci < c.count {
                if c[ci] == qc { found = ci; break }
                ci += 1
            }
            guard found >= 0 else { return nil }
            var gain = 10
            if found == lastMatch + 1 { gain += 15 }                       // 연속
            if found == 0 || isBoundary(original, at: found) { gain += 12 } // 단어/경로 시작
            if let start = fileNameStart, found >= start { gain += 8 }    // 파일 이름 안
            if lastMatch >= 0 { gain -= min(10, found - lastMatch - 1) }   // 간격
            score += gain
            positions.append(found)
            lastMatch = found
            ci = found + 1
        }
        // 짧은 후보 선호
        score -= min(30, c.count / 8)
        return Match(score: score, positions: positions)
    }

    private static func isBoundary(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        if previous == "/" || previous == "-" || previous == "_" || previous == " " || previous == "." { return true }
        return previous.isLowercase && chars[index].isUppercase
    }
}
