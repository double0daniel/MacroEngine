import SwiftUI

// MARK: - Hex helper

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Palette
// The whole UI lives in these slate tones. Color is reserved for `Accent`.

enum Slate {
    static let background    = Color(hex: 0x1B1E25) // app canvas (never pure black)
    static let surface       = Color(hex: 0x252932) // cards
    static let surfaceRaised = Color(hex: 0x2F3440) // icon wells, chips, buttons on cards
    static let stroke        = Color(hex: 0x3B414E) // hairlines and card borders
    static let track         = Color(hex: 0x343A46) // empty ring / bar track

    static let textPrimary   = Color(hex: 0xF3F4F6) // ~14:1 on background
    static let textSecondary = Color(hex: 0xB8BEC9) // ~8:1
    static let textTertiary  = Color(hex: 0x8D94A3) // ~4.7:1, captions only
}

/// The only saturated colors in the app: macro icons, rings and bars.
enum Accent {
    static let calories = Color(hex: 0xFF7A59)
    static let protein  = Color(hex: 0x4DA8FF)
    static let carbs    = Color(hex: 0xF2C94C)
    static let fat      = Color(hex: 0x5FD6A4)
}

// MARK: - Typography (all Dynamic Type text styles)

extension Font {
    static let meDisplay  = Font.system(.largeTitle, design: .default, weight: .bold).monospacedDigit()
    static let meHeadline = Font.system(.headline, design: .default, weight: .semibold)
    static let meBody     = Font.system(.subheadline, design: .default, weight: .regular)
    static let meCaption  = Font.system(.caption, design: .default, weight: .medium)
    static let meNumber   = Font.system(.body, design: .default, weight: .semibold).monospacedDigit()
}

// MARK: - Surfaces

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Slate.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Slate.stroke.opacity(0.6), lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }

    /// Full-screen slate canvas.
    func slateScreen() -> some View {
        background(Slate.background.ignoresSafeArea())
    }
}

// MARK: - Buttons

/// Monochrome primary action: near-white capsule, slate label.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.meHeadline)
            .foregroundStyle(Slate.background)
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Slate.textPrimary, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Quantity chip: filled when selected.
struct ChipStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.meCaption)
            .foregroundStyle(selected ? Slate.background : Slate.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Slate.textPrimary : Slate.surfaceRaised, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
