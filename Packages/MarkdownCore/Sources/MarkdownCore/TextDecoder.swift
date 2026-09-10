import Foundation

public struct DecodedText: Sendable {
    public var text: String
    public var encoding: String.Encoding
    public var hadBOM: Bool
}

/// 바이트 → 문자열. BOM, UTF-8, 그다음 CP949 → CP1252 → Latin-1 순서로 엄격 디코딩.
public enum TextDecoder {
    /// CP949(통합 완성형). EUC-KR을 포함한다.
    public static let cp949 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
    )

    public static func decode(_ data: Data) -> DecodedText {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return DecodedText(text: text, encoding: .utf8, hadBOM: true)
        }
        if data.starts(with: [0xFF, 0xFE]), let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return DecodedText(text: text, encoding: .utf16LittleEndian, hadBOM: true)
        }
        if data.starts(with: [0xFE, 0xFF]), let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return DecodedText(text: text, encoding: .utf16BigEndian, hadBOM: true)
        }
        if let text = String(data: data, encoding: .utf8) {
            return DecodedText(text: text, encoding: .utf8, hadBOM: false)
        }

        // UTF-8이 아니면 한국어 사용자에게 가장 흔한 CP949(EUC-KR 상위 집합)부터 엄격하게 시도한다.
        // 잘못된 바이트열이면 nil이 되어 다음 후보로 넘어간다. Latin-1은 항상 성공하는 마지막 후보다.
        for encoding in [cp949, .windowsCP1252, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) {
                return DecodedText(text: text, encoding: encoding, hadBOM: false)
            }
        }
        return DecodedText(text: String(decoding: data, as: UTF8.self), encoding: .utf8, hadBOM: false)
    }

    /// CRLF, CR → LF.
    public static func normalizeNewlines(_ text: String) -> String {
        guard text.contains("\r") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
