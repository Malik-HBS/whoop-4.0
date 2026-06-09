import SwiftUI

@main
struct OpenWhoopApp: App {
    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}

/// Thin root wrapper that creates a MetricsRepository and LiveViewModel synchronously (no
/// async window) and immediately injects them as environment objects so RootTabView + its
/// tabs always receive non-nil @EnvironmentObjects from the very first render frame.
///
/// LiveViewModel owns the single BLEManager / CBCentralManager. Creating it here (at app
/// launch) means state-restoration fires in the same process lifetime as the manager, and
/// both the Device tab and the Alarm sheet share the same BLE connection.
///
/// The MetricsRepository opens its on-disk store lazily (on the first load/refresh call),
/// so there is no need to wait for an async factory before showing the UI.
private struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var metrics: MetricsRepository
    @StateObject private var steps: StepCountingService
    @StateObject private var live: LiveViewModel
    @StateObject private var workouts: WorkoutManager
    @StateObject private var serverDiagnostics = ServerDiagnostics.shared
    @StateObject private var bleDiagnostics = BLEDiagnostics.shared

    init() {
        let metricsRepo = MetricsRepository(deviceId: AppConfig.deviceId)
        let stepService = StepCountingService()
        let liveModel = LiveViewModel(deviceId: AppConfig.deviceId,
                                      stepCountingService: stepService)
        _metrics = StateObject(wrappedValue: metricsRepo)
        _steps = StateObject(wrappedValue: stepService)
        _live = StateObject(wrappedValue: liveModel)
        _workouts = StateObject(wrappedValue: WorkoutManager(
            deviceId: AppConfig.deviceId,
            metrics: metricsRepo,
            liveState: liveModel.state
        ))
    }

    var body: some View {
        RootTabView()
            .environmentObject(metrics)
            .environmentObject(steps)
            .environmentObject(live)
            .environmentObject(workouts)
            .environmentObject(serverDiagnostics)
            .environmentObject(bleDiagnostics)
            .task {
                metrics.startLocalProcessing()
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    live.enterForeground()
                    metrics.noteAppForegrounded()
                case .background:
                    live.onEnterBackground()
                default:
                    break
                }
            }
    }
}
