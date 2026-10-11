import SwiftUI

// MARK: - Progress ring

struct RingGauge<Center: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: () -> Center

    @State private var shown: Double = 0

    private var clamped: Double { min(max(progress.isFinite ? progress : 0, 0), 1) }

    var body: some View {
        ZStack {
            Circle().stroke(Slate.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(shown > 0.001 ? 1 : 0)
            center()
        }
        .padding(lineWidth / 2)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = clamped } }
        .onChange(of: clamped) { _, newValue in
            withAnimation(.spring(duration: 0.6)) { shown = newValue }
        }
    }
}

// MARK: - Progress bar

struct BarGauge: View {
    var progress: Double
    var color: Color
    var height: CGFloat = 6

    @State private var shown: Double = 0

    private var clamped: Double { min(max(progress.isFinite ? progress : 0, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Slate.track)
                Capsule().fill(color).frame(width: geo.size.width * shown)
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = clamped } }
        .onChange(of: clamped) { _, newValue in
            withAnimation(.spring(duration: 0.5)) { shown = newValue }
        }
    }
}

// MARK: - Macro icon + chips

struct MacroIcon: View {
    let kind: MacroKind
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(kind.color)
            .frame(width: size, height: size)
            .background(Slate.surfaceRaised, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Compact protein / carbs / fat readout: colored glyphs, neutral numbers.
struct MacroChips: View {
    let macros: Macros

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MacroKind.macros) { kind in
                HStack(spacing: 4) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(kind.color)
                    Text("\(macros[kind].whole) g")
                        .font(.meCaption)
                        .foregroundStyle(Slate.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Protein \(macros.protein.whole) grams, carbs \(macros.carbs.whole) grams, fat \(macros.fat.whole) grams"
        )
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Slate.textSecondary)
                .frame(width: 64, height: 64)
                .background(Slate.surfaceRaised, in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .font(.meHeadline)
                .foregroundStyle(Slate.textPrimary)

            Text(message)
                .font(.meBody)
                .foregroundStyle(Slate.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .frame(maxWidth: 200)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
