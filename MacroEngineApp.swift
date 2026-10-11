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

    var body: some View {
        Group {
            if diary.hasCompletedOnboarding {
                DashboardView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: diary.hasCompletedOnboarding)
    }
}
