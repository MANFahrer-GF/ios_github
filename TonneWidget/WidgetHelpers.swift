import SwiftUI

extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if cleaned.count == 6 { cleaned += "FF" }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(.sRGB, red: Double((value >> 24) & 0xFF) / 255, green: Double((value >> 16) & 0xFF) / 255, blue: Double((value >> 8) & 0xFF) / 255, opacity: Double(value & 0xFF) / 255)
    }
}
