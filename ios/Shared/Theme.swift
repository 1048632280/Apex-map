import SwiftUI

// MARK: - 明暗

enum ThemeMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var toggled: ThemeMode {
        switch self {
        case .dark: return .light
        case .light: return .dark
        case .system: return .dark
        }
    }
}

// MARK: - 色板（Kelivo 的 SurfaceLadder 映射）

struct Palette {
    let page: Color
    let card: Color
    let fill: Color
    let hairline: Color
    let ink1: Color
    let ink2: Color
    let ink3: Color
    let ink4: Color
    let accent: Color
    let onAccent: Color
    let accentContainer: Color
    let onAccentContainer: Color

    static let light = Palette(
        page: Color(hex: 0xF7F7F7),
        card: Color(hex: 0xFEFEFE),
        fill: Color(hex: 0xEBEBEB),
        hairline: Color.black.opacity(0.06),
        ink1: Color(hex: 0x202020),
        ink2: Color(hex: 0x202020).opacity(0.72),
        ink3: Color(hex: 0x202020).opacity(0.50),
        ink4: Color(hex: 0x202020).opacity(0.30),
        accent: Color(hex: 0xB3262E),
        onAccent: .white,
        accentContainer: Color(hex: 0xFFDAD9),
        onAccentContainer: Color(hex: 0x410007)
    )

    static let dark = Palette(
        page: Color(hex: 0x121213),
        card: Color(hex: 0x2A2A2B),
        fill: Color(hex: 0x373738),
        hairline: Color.white.opacity(0.08),
        ink1: Color(hex: 0xF9F9F9),
        ink2: Color(hex: 0xF9F9F9).opacity(0.72),
        ink3: Color(hex: 0xF9F9F9).opacity(0.50),
        ink4: Color(hex: 0xF9F9F9).opacity(0.30),
        accent: Color(hex: 0xFFB4B8),
        onAccent: Color(hex: 0x5F1116),
        accentContainer: Color(hex: 0x7F2A2F),
        onAccentContainer: Color(hex: 0xFFDAD9)
    )

    static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - 字号阶梯

enum TypeScale {
    static let title = Font.system(size: 22, weight: .bold)
    static let mapName = Font.system(size: 32, weight: .heavy)
    static let section = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let name = Font.system(size: 17, weight: .semibold)
    static let label = Font.system(size: 12, weight: .regular)
    static let badge = Font.system(size: 11, weight: .semibold)
    static let metric = Font.system(size: 26, weight: .semibold).monospacedDigit()
}

// MARK: - 工具

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct CardBackground: ViewModifier {
    let palette: Palette
    var radius: CGFloat = 12
    var bordered = true

    func body(content: Content) -> some View {
        content
            .background(palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 1)
                }
            }
    }
}

extension View {
    func card(_ palette: Palette, radius: CGFloat = 12, bordered: Bool = true) -> some View {
        modifier(CardBackground(palette: palette, radius: radius, bordered: bordered))
    }
}
