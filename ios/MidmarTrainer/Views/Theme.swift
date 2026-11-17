import SwiftUI
import UIKit

/// Pool-deck colours: deep lane-water teal, buoy orange for actions, and a colour per workout type.
enum Palette {
    static let bg = dyn(0xEDF1EE, 0x0A1512)
    static let surface = dyn(0xFFFFFF, 0x11221D)
    static let ink = dyn(0x0F211C, 0xE5EFEA)
    static let muted = dyn(0x566A63, 0x8DA39A)
    static let line = dyn(0xD3DCD7, 0x223630)
    static let water = dyn(0x17594D, 0x66C7AD)
    static let waterSoft = dyn(0xDCEBE6, 0x17332C)
    static let buoy = dyn(0xC2410C, 0xFF8A55)
    static let pool = dyn(0x0E3F37, 0x0F2C26)
    static let poolInk = Color(hex: 0xF1F7F4)
    static let poolMuted = Color(hex: 0xA9C7BD)
    static let poolLine = Color(hex: 0x2A5C52)
    static let pop = Color(hex: 0xFF8A55)
    static let onPop = Color(hex: 0x1B0B03)

    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension SessionType {
    /// Colour on the normal page
    var color: Color {
        switch self {
        case .tech: Palette.dyn(0x17594D, 0x66C7AD)
        case .build, .thr, .pyr: Palette.dyn(0x6D38D4, 0xC4A7FF)
        case .speed: Palette.dyn(0xB5175B, 0xFF8FB8)
        case .easy: Palette.dyn(0x4A7410, 0xA8D568)
        case .long: Palette.dyn(0x1D4ED8, 0x8AB4FF)
        case .tt: Palette.dyn(0x8A5A06, 0xF2C14E)
        case .race: Palette.dyn(0xC2410C, 0xFF8A55)
        }
    }

    /// Colour on the dark pool card
    var brightColor: Color {
        switch self {
        case .tech: Color(hex: 0x66C7AD)
        case .build, .thr, .pyr: Color(hex: 0xC4A7FF)
        case .speed: Color(hex: 0xFF8FB8)
        case .easy: Color(hex: 0xA8D568)
        case .long: Color(hex: 0x8AB4FF)
        case .tt: Color(hex: 0xF2C14E)
        case .race: Color(hex: 0xFF8A55)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// Condensed numerals and headings, like a pace clock.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
    static let eyebrow = Font.system(size: 12, weight: .semibold)
}

struct Eyebrow: View {
    let text: String
    var color: Color = Palette.muted
    var body: some View {
        Text(text.uppercased()).font(.eyebrow).tracking(1.4).foregroundStyle(color)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }
}

struct TypeChip: View {
    let type: SessionType
    var onPool = false
    var body: some View {
        let c = onPool ? type.brightColor : type.color
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(type.name.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.8)
        }
        .foregroundStyle(c)
        .padding(.vertical, 4).padding(.horizontal, 10)
        .background(c.opacity(onPool ? 0.16 : 0.13), in: Capsule())
    }
}

/// One to four bars showing how hard a set is.
struct EffortPips: View {
    let level: Int
    var color: Color = Palette.ink
    var off: Color = Palette.line
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(i <= level ? color : off).frame(width: 4, height: 11)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Palette.buoy
    var text: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(text)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Palette.ink)
            .background(configuration.isPressed ? Palette.line.opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1.5))
    }
}

/// A row of alternating buoys on a line: the lane rope under the header.
struct LaneRope: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)), with: .color(Palette.line))
            var x: CGFloat = 5, i = 0
            while x < size.width {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: size.height / 2 - 3.5, width: 7, height: 7)),
                         with: .color(i % 2 == 0 ? Palette.buoy : Palette.water))
                x += 10; i += 1
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
