import SwiftUI
import WhoopStore

struct StrainDetailView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var workoutManager: WorkoutManager
    @EnvironmentObject private var steps: StepCountingService

    @State private var dailyRows: [DailyMetric] = []
    @State private var isLoading = true

    private var todayStrain: Double {
        workoutManager.todaysSummary?.score ?? metrics.today?.strain ?? 0
    }

    private var strainProgress: Double {
        min(1, max(0, todayStrain / 21))
    }

    private var zoneDurations: (low: TimeInterval, high: TimeInterval) {
        let sessions = todaysSessions
        let low = sessions.reduce(0.0) { partial, session in
            partial + duration(for: [1, 2, 3], in: session)
        }
        let high = sessions.reduce(0.0) { partial, session in
            partial + duration(for: [4, 5], in: session)
        }
        return (low, high)
    }

    private var strengthDuration: TimeInterval {
        todaysSessions
            .filter(\.isStrengthWorkout)
            .reduce(0) { $0 + $1.duration }
    }

    private var todaysSessions: [WorkoutSession] {
        let formatter = Self.utcDayFormatter
        let today = formatter.string(from: Date())
        return workoutManager.recentCompletedSessions.filter {
            formatter.string(from: $0.startTime) == today
        }
    }

    private var comparison: (strainDelta: Double?, stepDelta: Int?) {
        let trailing = Array(dailyRows.suffix(30))
        let prior = trailing.dropLast().compactMap { $0.strain }
        let avgStrain = prior.isEmpty ? nil : prior.reduce(0, +) / Double(prior.count)

        let stepSummaries = steps.dailySummaries(endingAt: Date(), days: 30)
        let priorSteps = stepSummaries.dropLast().map(\.totalSteps)
        let avgSteps = priorSteps.isEmpty ? nil : priorSteps.reduce(0, +) / priorSteps.count

        let strainDelta = avgStrain.map { todayStrain - $0 }
        let stepDelta = avgSteps.map { steps.state.dailySteps - $0 }
        return (strainDelta, stepDelta)
    }

    var body: some View {
        ZStack {
            strainBackground.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(WH.Color.textSecondary)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: WH.Spacing.lg) {
                        heroSection
                        breakdownCard
                        comparisonCard
                        insightCard
                    }
                    .padding(.horizontal, WH.Spacing.md)
                    .padding(.top, WH.Spacing.md)
                    .padding(.bottom, WH.Spacing.xxl)
                }
            }
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await load()
        }
    }

    private var heroSection: some View {
        VStack(spacing: WH.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 28)

                Circle()
                    .trim(from: 0, to: strainProgress)
                    .stroke(
                        AngularGradient(
                            colors: [Color(hex: "#5BC7FF"), WH.Color.strainBlue],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(250)
                        ),
                        style: StrokeStyle(lineWidth: 28, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Bottom markers for a WHOOP-like split in the ring without extra callouts.
                ForEach([-20.0, 0.0, 20.0], id: \.self) { angle in
                    Capsule()
                        .fill(angle == 0 ? Color.white : Color.white.opacity(0.18))
                        .frame(width: 8, height: angle == 0 ? 28 : 18)
                        .offset(y: 162)
                        .rotationEffect(.degrees(angle))
                }

                VStack(spacing: 8) {
                    Text("WHOOP")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.9))
                        .tracking(2.6)
                    Text(String(format: "%.1f", todayStrain))
                        .font(.system(size: 82, weight: .black, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()
                    Text("STRAIN")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(WH.Color.textPrimary)
                        .tracking(2.4)
                }
            }
            .frame(width: 352, height: 352)

            Text(strainHeadline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WH.Spacing.md)
        }
    }

    private var breakdownCard: some View {
        VStack(spacing: 0) {
            breakdownRow(
                icon: "heart",
                title: "Heart Rate Zones 1-3",
                primary: formatClock(zoneDurations.low),
                secondary: formatComparisonClock(totalActiveDuration)
            )
            divider
            breakdownRow(
                icon: "heart.fill",
                title: "Heart Rate Zones 4-5",
                primary: formatClock(zoneDurations.high),
                secondary: formatComparisonClock(totalActiveDuration)
            )
            divider
            breakdownRow(
                icon: "dumbbell",
                title: "Strength Activity Time",
                primary: formatClock(strengthDuration),
                secondary: formatComparisonClock(totalActiveDuration)
            )
            divider
            breakdownRow(
                icon: "figure.walk",
                title: "Steps",
                primary: steps.state.dailySteps.formatted(),
                secondary: comparison.stepDelta.map { deltaText(for: $0) } ?? "30-day avg"
            )
        }
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color(hex: "#232733").opacity(0.96), Color(hex: "#12151B").opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(alignment: .top) {
            DiamondPointer()
                .fill(Color(hex: "#232733").opacity(0.98))
                .frame(width: 24, height: 14)
                .offset(y: -8)
        }
    }

    private func breakdownRow(icon: String, title: String, primary: String, secondary: String) -> some View {
        HStack(spacing: WH.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.76))
                .frame(width: 28)

            Text(title.uppercased())
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WH.Color.textPrimary.opacity(0.92))
                .tracking(1.4)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(primary)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                Text(secondary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, 18)
    }

    private var comparisonCard: some View {
        HStack(spacing: 10) {
            comparisonChip(
                title: "Today vs. last 30 days",
                strainDelta: comparison.strainDelta
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func comparisonChip(title: String, strainDelta: Double?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: strainDelta.map { $0 >= 0 ? "triangle.fill" : "triangle.fill" } ?? "circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(strainDelta.map { $0 >= 0 ? WH.Color.recoveryGreen : WH.Color.recoveryYellow } ?? WH.Color.textSecondary)
                .rotationEffect(.degrees((strainDelta ?? 0) >= 0 ? 0 : 180))
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WH.Color.textPrimary)
            if let strainDelta {
                Text(deltaText(for: strainDelta, precision: 1))
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(strainDelta >= 0 ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
            }
        }
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.md) {
            Text(strainInsight)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WH.Color.textPrimary.opacity(0.95))
                .lineSpacing(4)

            HStack(spacing: WH.Spacing.sm) {
                miniTag(title: "Workout strain", value: String(format: "%.1f", workoutManager.todaysSummary?.score ?? 0))
                miniTag(title: "Daily load", value: String(format: "%.0f", workoutManager.todaysSummary?.totalLoad ?? 0))
            }
        }
        .padding(WH.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1D2130"), Color(hex: "#131720")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: "#355F82"), lineWidth: 1.5)
        )
    }

    private func miniTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: Capsule())
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, WH.Spacing.md)
    }

    private var totalActiveDuration: TimeInterval {
        todaysSessions.reduce(0) { $0 + $1.duration }
    }

    private var strainHeadline: String {
        switch todayStrain {
        case 0..<5:
            return "You are still in a light-load range today."
        case 5..<11:
            return "You are building a moderate amount of strain today."
        case 11..<16:
            return "This is a productive training load for today."
        default:
            return "You are pushing into a high strain day."
        }
    }

    private var strainInsight: String {
        let hasStrength = strengthDuration > 0
        switch todayStrain {
        case 0..<5:
            return hasStrength
                ? "Your body is handling light work today. If recovery feels good, you still have room to add effort without overreaching."
                : "Your body is still early in the day’s load. A moderate session or a steady walk would move strain upward without forcing the pace."
        case 5..<11:
            return "Your body is capable of taking on moderate effort today. To keep momentum while balancing recovery, aim for controlled work instead of a late spike."
        case 11..<16:
            return "You’re in a solid training range. Another hard block is possible, but consistency will come from respecting recovery tonight."
        default:
            return "You’ve accumulated a heavy strain load. Focus on hydration, mobility, and sleep so this effort turns into adaptation instead of carryover fatigue."
        }
    }

    private var strainBackground: some View {
        LinearGradient(
            colors: [Color(hex: "#2E3744"), Color(hex: "#161B24"), Color(hex: "#0B0D12")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func load() async {
        let calendar = Calendar(identifier: .gregorian)
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -40, to: end) ?? end
        dailyRows = await metrics.daily(fromDay: Self.utcDayFormatter.string(from: start),
                                        toDay: Self.utcDayFormatter.string(from: end))
        isLoading = false
    }

    private func duration(for zones: [Int], in session: WorkoutSession) -> TimeInterval {
        let percentages = session.zoneBreakdown.percentages
        let ratio = zones.reduce(0.0) { $0 + (percentages[$1] ?? 0) / 100.0 }
        return session.duration * ratio
    }

    private func formatClock(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    private func formatComparisonClock(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func deltaText(for value: Int) -> String {
        if value == 0 { return "At average" }
        return value > 0 ? "+\(value.formatted())" : "\(value.formatted())"
    }

    private func deltaText(for value: Double, precision: Int) -> String {
        if value == 0 { return "At average" }
        return value > 0 ? String(format: "+%.\(precision)f", value) : String(format: "%.\(precision)f", value)
    }

    private static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct DiamondPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    let metrics = MetricsRepository(deviceId: "preview")
    let live = LiveViewModel(deviceId: "preview")
    StrainDetailView()
        .environmentObject(metrics)
        .environmentObject(WorkoutManager(deviceId: "preview", metrics: metrics, liveState: live.state))
        .environmentObject(StepCountingService())
}
