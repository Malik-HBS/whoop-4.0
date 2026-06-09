import SwiftUI

// MARK: - HealthView
// Empty placeholder for the Health tab while the section is being defined.

struct HealthView: View {
    @EnvironmentObject private var live: LiveViewModel
    @EnvironmentObject private var steps: StepCountingService

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: WH.Spacing.lg) {
                        ScreenHeader("Health")
                        NavigationLink(destination: StepTrendView()) {
                            stepsTile
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, WH.Spacing.md)
                    .padding(.top, WH.Spacing.sm)
                    .padding(.bottom, WH.Spacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(WH.Color.background)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            steps.refreshAvailability(connected: live.state.connected)
        }
    }

    private var stepsTile: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STEPS TODAY")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(WH.Color.textSecondary)
                            .tracking(1.2)
                        Text(stepAvailabilityText)
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }

                    Spacer()

                    Text(stepCountText)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                ProgressView(value: min(Double(steps.state.dailySteps), Double(steps.state.dailyGoal)),
                             total: Double(steps.state.dailyGoal))
                    .tint(Color(hex: "#7BD88F"))
                    .background(WH.Color.surface2, in: Capsule())

                HStack {
                    Label("Goal \(steps.state.dailyGoal.formatted())", systemImage: "figure.walk")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)

                    Spacer()

                    if let cadence = steps.state.currentCadenceSpm,
                       steps.state.isWalkingLikeMotion {
                        Text("\(Int(cadence.rounded())) spm")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var stepCountText: String {
        switch steps.state.availability {
        case .noDevice, .waitingForData:
            return "--"
        case .active, .stale:
            return steps.state.dailySteps.formatted()
        }
    }

    private var stepAvailabilityText: String {
        switch steps.state.availability {
        case .noDevice:
            return "Connect WHOOP to start counting"
        case .waitingForData:
            return "Waiting for motion data"
        case .active:
            return "Goal \(steps.state.dailyGoal.formatted())"
        case .stale:
            return "Motion data is stale"
        }
    }
}

#Preview("Health") {
    HealthView()
        .environmentObject(LiveViewModel(deviceId: "preview"))
        .environmentObject(StepCountingService())
}
