import SwiftUI
import UIKit

// MascotAvatarView: "Macro", the MacroEngine AI coach.
// Depends on Theme.swift (Slate, Accent, Font.me*, .card(), .slateScreen()). iOS 17+.

// MARK: - State

enum MascotState: String, CaseIterable, Hashable, Sendable {
    case neutral, coaching, celebrating

    var symbol: String {
        switch self {
        case .neutral: "bolt.fill"
        case .coaching: "cpu.fill"
        case .celebrating: "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .neutral: "Ready to crush today"
        case .coaching: "Analyzing macros…"
        case .celebrating: "Goal hit! 🎉"
        }
    }

    var imageAssetName: String {
        switch self {
        case .neutral: "MacroEngine-Mascot-Neutral"
        case .coaching: "MacroEngine-Mascot-Coaching"
        case .celebrating: "MacroEngine-Mascot-Celebrating"
        }
    }
}

private enum MascotPalette {
    static let online = Color(hex: 0x4ADE80)
    static let coralHighlight = Color(hex: 0xFFB59E)
}

// MARK: - Badge (the round avatar on its own)

struct MascotBadge: View {
    let state: MascotState
    let diameter: CGFloat
    var isOnline = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var coral: Color { Accent.calories }
    private var ringWidth: CGFloat { max(1.5, diameter * 0.045) }
    private var dotSize: CGFloat { max(8, diameter * 0.26) }
    private var artwork: UIImage? { UIImage(named: state.imageAssetName) }

    private var glowStrength: Double {
        switch state {
        case .neutral: 0.28
        case .coaching: 0.40
        case .celebrating: 0.55
        }
    }

    var body: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .bottomTrailing) {
                        if !isOnline {
                            Circle()
                                .fill(Slate.background)
                                .frame(width: diameter * 0.2, height: diameter * 0.2)
                                .overlay {
                                    Circle()
                                        .fill(Slate.textTertiary)
                                        .padding(diameter * 0.04)
                                }
                                .offset(x: -diameter * 0.28, y: -diameter * 0.28)
                        }
                    }
            } else {
                fallbackBadge
                    .background { glow }
                    .overlay(alignment: .bottomTrailing) {
                        MascotStatusDot(size: dotSize, border: max(2, dotSize * 0.22),
                                        isOnline: isOnline, animate: !reduceMotion)
                    }
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.smooth(duration: 0.35), value: state)
    }

    private var fallbackBadge: some View {
        ZStack {
            Circle().fill(Slate.surface)
            Circle().fill(
                LinearGradient(colors: [coral.opacity(0.30), coral.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            ring
            Image(systemName: state.symbol)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(Slate.textPrimary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: state == .coaching && !reduceMotion)
                .symbolEffect(.bounce, value: state)
        }
    }

    @ViewBuilder private var ring: some View {
        switch state {
        case .neutral:
            Circle().strokeBorder(coral.opacity(0.35), lineWidth: ringWidth)
        case .coaching:
            Circle().strokeBorder(Slate.stroke, lineWidth: ringWidth)
            SpinningArc(color: coral, lineWidth: ringWidth, animate: !reduceMotion)
        case .celebrating:
            Circle().strokeBorder(
                AngularGradient(colors: [coral, MascotPalette.coralHighlight, coral], center: .center),
                lineWidth: ringWidth
            )
        }
    }

    private var glow: some View {
        Circle()
            .fill(RadialGradient(colors: [coral.opacity(glowStrength), coral.opacity(0)],
                                 center: .center,
                                 startRadius: diameter * 0.2,
                                 endRadius: diameter * 0.85))
            .frame(width: diameter * 1.7, height: diameter * 1.7)
            .allowsHitTesting(false)
    }
}

private struct SpinningArc: View {
    let color: Color
    let lineWidth: CGFloat
    let animate: Bool

    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .padding(lineWidth / 2)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                guard animate else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

private struct MascotStatusDot: View {
    let size: CGFloat
    let border: CGFloat
    let isOnline: Bool
    let animate: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            // Slate cut-out so the dot reads cleanly against the avatar.
            Circle().fill(Slate.background)
                .frame(width: size + border * 2, height: size + border * 2)

            if isOnline {
                Circle().fill(MascotPalette.online.opacity(0.4))
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 2.0 : 1)
                    .opacity(pulse ? 0 : 1)
            }

            Circle().fill(isOnline ? MascotPalette.online : Slate.textTertiary)
                .frame(width: size, height: size)
        }
        .onAppear {
            guard isOnline, animate else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Avatar view (badge + name + subtitle)

struct MascotAvatarView: View {
    enum Size: CGFloat, CaseIterable {
        case compact = 32   // dashboard header trailing slot
        case regular = 44   // intake banners
        case large = 64     // AI coach card
        case hero = 96      // empty states / onboarding
    }

    enum Layout {
        case badge      // avatar only
        case inline     // avatar left, text right
        case stacked    // avatar above centred text
    }

    var state: MascotState = .neutral
    var size: Size = .regular
    var layout: Layout = .inline
    /// Overrides the default line for the current state.
    var subtitle: String? = nil
    var isOnline = true

    @ScaledMetric(relativeTo: .headline) private var scale: CGFloat = 1

    private var diameter: CGFloat { size.rawValue * min(scale, 1.35) }
    private var resolvedSubtitle: String { subtitle ?? state.subtitle }

    private var titleFont: Font {
        size.rawValue >= Size.large.rawValue ? .system(.title3, weight: .bold) : .meHeadline
    }
    private var subtitleFont: Font { size == .compact ? .meCaption : .meBody }

    var body: some View {
        Group {
            switch layout {
            case .badge:
                badge
            case .inline:
                HStack(spacing: diameter * 0.3) {
                    badge
                    VStack(alignment: .leading, spacing: 2) { title; subtitleText }
                }
            case .stacked:
                VStack(spacing: diameter * 0.18) {
                    badge
                    VStack(spacing: 2) { title; subtitleText }
                        .multilineTextAlignment(.center)
                }
            }
        }
        .sensoryFeedback(.success, trigger: state) { _, new in new == .celebrating }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Macro, AI coach, \(isOnline ? "online" : "offline")")
        .accessibilityValue(resolvedSubtitle)
    }

    private var badge: some View {
        MascotBadge(state: state, diameter: diameter, isOnline: isOnline)
    }

    private var title: some View {
        Text("Macro")
            .font(titleFont)
            .foregroundStyle(Slate.textPrimary)
    }

    private var subtitleText: some View {
        Text(resolvedSubtitle)
            .font(subtitleFont)
            .foregroundStyle(Slate.textSecondary)
            .contentTransition(.opacity)
            .animation(.smooth(duration: 0.25), value: resolvedSubtitle)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("States and sizes") {
    VStack(spacing: 32) {
        ForEach(MascotState.allCases, id: \.self) { state in
            HStack(spacing: 28) {
                ForEach(MascotAvatarView.Size.allCases, id: \.self) { size in
                    MascotAvatarView(state: state, size: size, layout: .badge)
                }
            }
        }
    }
    .padding(40)
    .slateScreen()
    .preferredColorScheme(.dark)
}

#Preview("In context") {
    ScrollView {
        VStack(spacing: 16) {
            // Dashboard header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.system(.largeTitle, weight: .bold)).foregroundStyle(Slate.textPrimary)
                    Text("Sunday, October 11").font(.meBody).foregroundStyle(Slate.textSecondary)
                }
                Spacer()
                MascotAvatarView(state: .neutral, size: .compact, layout: .badge)
            }

            // Intake banner
            MascotAvatarView(state: .celebrating, size: .regular, layout: .inline,
                             subtitle: "Protein goal hit! 🎉")
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

            // AI coach card
            VStack(spacing: 16) {
                MascotAvatarView(state: .coaching, size: .large, layout: .stacked)
                Text("You're 38 g short on protein. A Greek yoghurt would close most of the gap.")
                    .font(.meBody)
                    .foregroundStyle(Slate.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .card(padding: 24)
        }
        .padding(20)
    }
    .slateScreen()
    .preferredColorScheme(.dark)
}

#Preview("Playground") {
    @Previewable @State var state: MascotState = .neutral
    VStack(spacing: 32) {
        MascotAvatarView(state: state, size: .hero, layout: .stacked)
        Picker("State", selection: $state) {
            ForEach(MascotState.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        .pickerStyle(.segmented)
    }
    .padding(32)
    .slateScreen()
    .preferredColorScheme(.dark)
}
#endif
