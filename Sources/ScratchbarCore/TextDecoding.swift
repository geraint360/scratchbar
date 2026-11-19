import Foundation

/// Decodes file contents as UTF-8, falling back to Windows-1252 and then
/// MacRoman (which accepts any bytes), so a stray non-UTF-8 file still opens.
public func decodeText(_ data: Data) -> String {
    if let s = String(data: data, encoding: .utf8) { return s }
    if let s = String(data: data, encoding: .windowsCP1252) { return s }
    // MacRoman maps every byte, so this only falls through in theory.
    return String(data: data, encoding: .macOSRoman) ?? String(decoding: data, as: UTF8.self)
}

/// Decodes the first bytes of a file for a title. When the read was cut short
/// the cut may land inside a UTF-8 sequence, so up to 3 trailing bytes are
/// dropped before falling back to `decodeText`.
func decodePrefix(_ data: Data, truncated: Bool) -> String {
    guard truncated else { return decodeText(data) }
    for drop in 0...min(3, data.count) {
        if let s = String(data: data.dropLast(drop), encoding: .utf8) { return s }
    }
    return decodeText(data)
}
