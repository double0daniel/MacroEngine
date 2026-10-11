import SwiftUI

@main
struct MacroEngineApp: App {
    @State private var diary = DiaryStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(diary)
                .preferredColorScheme(.dark)
        }
    }
}

private struct AppRootView: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage = 1

    var body: some View {
        Group {
            if diary.hasCompletedOnboarding {
                VStack(spacing: 0) {
                    pageIndicator
                    TabView(selection: $selectedPage) {
                        TelemetryView()
                            .tag(0)
                        DashboardView()
                            .tag(1)
                        SettingsView()
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .tint(Slate.textPrimary)
                .slateScreen()
                .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: diary.hasCompletedOnboarding)
        .onAppear {
            diary.processRollover()
            diary.refreshFromWidgetData()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                diary.processRollover()
                diary.refreshFromWidgetData()
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            pageButton("Telemetry", symbol: "chart.xyaxis.line", index: 0)
            pageButton("Today", symbol: "circle.grid.2x2.fill", index: 1)
            pageButton("Settings", symbol: "slider.horizontal.3", index: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Slate.background)
    }

    private func pageButton(_ title: String, symbol: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { selectedPage = index }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.meCaption.weight(selectedPage == index ? .semibold : .medium))
            .foregroundStyle(selectedPage == index ? Slate.textPrimary : Slate.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedPage == index ? Slate.surfaceRaised : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedPage == index ? .isSelected : [])
    }
}
