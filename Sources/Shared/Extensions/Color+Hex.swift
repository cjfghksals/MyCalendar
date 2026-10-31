import SwiftUI
import UIKit

/// HEX 색상 문자열 변환. "#RGB", "#RRGGBB", "#RRGGBBAA" 형식을 지원하고 "#"은 생략할 수 있다.
enum HexColor {
    typealias Components = (red: Double, green: Double, blue: Double, alpha: Double)

    /// HEX 문자열 → 0...1 범위의 RGBA. 형식이 잘못되면 nil
    static func components(from hex: String) -> Components? {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard [3, 6, 8].contains(string.count),
              string.allSatisfy(\.isHexDigit),
              let value = UInt64(string, radix: 16) else {
            return nil
        }

        switch string.count {
        case 3:
            return (
                red: Double((value >> 8) & 0xF) * 17 / 255,
                green: Double((value >> 4) & 0xF) * 17 / 255,
                blue: Double(value & 0xF) * 17 / 255,
                alpha: 1
            )
        case 6:
            return (
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                alpha: 1
            )
        default:
            return (
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    /// 0...1 범위의 RGBA → "#RRGGBB" (불투명하지 않으면 "#RRGGBBAA")
    static func string(red: Double, green: Double, blue: Double, alpha: Double = 1) -> String {
        func byte(_ component: Double) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        let alphaByte = byte(alpha)
        if alphaByte == 255 {
            return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        }
        return String(format: "#%02X%02X%02X%02X", byte(red), byte(green), byte(blue), alphaByte)
    }
}

extension Color {
    /// HEX 문자열로 색을 만든다. 형식이 잘못되면 nil
    init?(hex: String) {
        guard let components = HexColor.components(from: hex) else { return nil }
        self.init(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }

    /// HEX 문자열로 색을 만들고, 값이 없거나 잘못되면 fallback을 쓴다.
    init(hex: String?, fallback: Color) {
        if let hex, let color = Color(hex: hex) {
            self = color
        } else {
            self = fallback
        }
    }

    /// 현재 색을 HEX 문자열로 변환한다 (설정 화면의 색상 선택기 저장용).
    func hexString() -> String? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return HexColor.string(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }
}
