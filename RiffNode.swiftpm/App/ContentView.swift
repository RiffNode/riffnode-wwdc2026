import SwiftUI

// MARK: - Main Content View
// Liquid Glass UI Design - iOS 26+ Design Language

struct ContentView: View {

    // MARK: - Dependencies (Dependency Injection)

    @State private var engine = AudioEngineManager()
    @State private var presetService = PresetService()

    // MARK: - State

    enum AppState {
        case welcome
        case guidedTour
        case main
    }

    @State private var appState: AppState = .welcome

    // MARK: - Body

    var body: some View {
        ZStack {
            AdaptiveBackground()

            switch appState {
            case .welcome:
                WelcomeView(
                    engine: engine,
                    onStartTour: {
                        withAnimation(.spring(duration: 0.5)) {
                            appState = .guidedTour
                        }
                    },
                    onSkipToMain: {
                        withAnimation(.spring(duration: 0.5)) {
                            appState = .main
                        }
                    }
                )

            case .guidedTour:
                GuidedTourView(engine: engine) {
                    withAnimation(.spring(duration: 0.5)) {
                        appState = .main
                    }
                }

            case .main:
                MainInterfaceView(
                    engine: engine,
                    presetService: presetService
                )
            }
        }
        // Follows the system appearance – dark mode suits the dark pedal hardware on stage
        #if os(macOS)
        .frame(minWidth: 1000, minHeight: 700)
        #endif
    }
}


// MARK: - Preview

#Preview {
    ContentView()
}
