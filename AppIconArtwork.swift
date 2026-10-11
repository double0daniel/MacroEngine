import SwiftUI

// Draws the MacroEngine app icon in code so you can export an exact 1024 x 1024 PNG.
// The bolt is a custom Path (not an SF Symbol) because Apple's SF Symbols license
// doesn't allow symbols inside app icons or logos.

struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit: [(CGFloat, CGFloat)] = [(56, 0), (20, 56), (44, 56), (36, 100), (80, 40), (55, 40)]
        let points = unit.map {
            CGPoint(x: rect.minX + $0.0 / 100 * rect.width,
                    y: rect.minY + $0.1 / 100 * rect.height)
        }
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

struct AppIconArtwork: View {
    enum Variant { case standard, tinted }
    var variant: Variant = .standard

    private struct Segment { let start: Double; let color: Color }

    private var segments: [Segment] {
        switch variant {
        case .standard:
            [Segment(start: 0.0467, color: Color(hex: 0x4DA8FF)),   // protein
             Segment(start: 0.3800, color: Color(hex: 0xF2C94C)),   // carbs
             Segment(start: 0.7133, color: Color(hex: 0x5FD6A4))]   // fat
        case .tinted:
            [Segment(start: 0.0467, color: Color(hex: 0xFFFFFF)),
             Segment(start: 0.3800, color: Color(hex: 0xBDBDBD)),
             Segment(start: 0.7133, color: Color(hex: 0x8A8A8A))]
        }
    }

    private var backgroundColors: [Color] {
        switch variant {
        case .standard: [Color(hex: 0x2C313C), Color(hex: 0x16191F)]
        case .tinted:   [Color(hex: 0x262626), Color(hex: 0x0D0D0D)]
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: backgroundColors, startPoint: .top, endPoint: .bottom)

            ZStack {
                ForEach(0..<segments.count, id: \.self) { index in
                    Circle()
                        .trim(from: segments[index].start, to: segments[index].start + 0.24)
                        .stroke(segments[index].color,
                                style: StrokeStyle(lineWidth: 78, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 640, height: 640)

            BoltShape()
                .fill(Color(hex: 0xF3F4F6))
                .overlay(BoltShape().stroke(Color(hex: 0xF3F4F6), style: StrokeStyle(lineWidth: 14, lineJoin: .round)))
                .frame(width: 236, height: 320)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Call once (for example from a temporary button) and copy the PNG out of the app's Documents folder.
@MainActor
enum IconExporter {
    static func export() {
        for (name, variant) in [("MacroEngine-AppIcon-1024", AppIconArtwork.Variant.standard),
                                ("MacroEngine-AppIcon-1024-tinted", .tinted)] {
            let renderer = ImageRenderer(content: AppIconArtwork(variant: variant))
            renderer.scale = 1          // 1024 pt at scale 1 = 1024 px
            renderer.isOpaque = true    // App Store icons can't contain transparency
            guard let data = renderer.uiImage?.pngData() else { continue }
            let url = URL.documentsDirectory.appending(path: "\(name).png")
            try? data.write(to: url)
            print("Icon written to:", url.path)
        }
    }
}

#if DEBUG
#Preview {
    AppIconArtwork()
        .scaleEffect(0.3)
        .frame(width: 308, height: 308)
        .clipShape(RoundedRectangle(cornerRadius: 68, style: .continuous))
        .padding()
        .background(Color(hex: 0x1B1E25))
}
#endif
