import Foundation
import Testing
@testable import MarkdownCore

struct TextDecoderTests {
    @Test func utf8WithBOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("# 안녕".utf8)
        let decoded = TextDecoder.decode(data)
        #expect(decoded.text == "# 안녕")
        #expect(decoded.hadBOM)
    }

    @Test func utf16LittleEndianWithBOM() {
        var data = Data([0xFF, 0xFE])
        data += "hi".data(using: .utf16LittleEndian)!
        let decoded = TextDecoder.decode(data)
        #expect(decoded.text == "hi")
        #expect(decoded.encoding == .utf16LittleEndian)
    }

    @Test func eucKRFallback() {
        // "한글" in EUC-KR
        let data = Data([0xC7, 0xD1, 0xB1, 0xDB])
        let decoded = TextDecoder.decode(data)
        #expect(decoded.text == "한글")
        #expect(decoded.encoding == TextDecoder.cp949)
    }

    @Test func normalizesNewlines() {
        #expect(TextDecoder.normalizeNewlines("a\r\nb\rc\n") == "a\nb\nc\n")
    }
}
