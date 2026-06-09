import SwiftUI

// MARK: - TodayView
// Dashboard-only redesign based on DesignHandoff. Data still flows through the existing
// MetricsRepository and LiveViewModel; no Bluetooth, sync, model, or algorithm logic lives here.

struct TodayView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @EnvironmentObject private var live: LiveViewModel
    @EnvironmentObject private var workoutManager: WorkoutManager
    @EnvironmentObject private var serverDiagnostics: ServerDiagnostics

    @State private var showingAlarm = false
    @State private var recoveryScore: RecoveryScore?

    @AppStorage(AlarmKeys.enabled) private var alarmEnabled = false
    @AppStorage(AlarmKeys.wakeByHour) private var wakeByHour = 7
    @AppStorage(AlarmKeys.wakeByMinute) private var wakeByMinute = 0

    private var recoveryPercent: Double? {
        recoveryScore?.score.map(Double.init) ?? metrics.today?.recovery.map { $0 * 100 }
    }

    private var strainValue: Double? {
        workoutManager.todaysSummary?.score ?? metrics.today?.strain
    }

    private var hrvValue: Double? {
        metrics.today?.avgHrv ?? metrics.lastNight?.avgHrv
    }

    private var rhrValue: Int? {
        metrics.today?.restingHr ?? metrics.lastNight?.restingHr
    }

    private var sleepMinutes: Double? {
        if let minutes = metrics.today?.totalSleepMin, minutes > 0 { return minutes }
        if let session = metrics.lastNight {
            let duration = Double(session.endTs - session.startTs) / 60
            return duration > 0 ? duration : nil
        }
        return nil
    }

    private var sleepEfficiency: Double? {
        guard sleepMinutes != nil else { return nil }
        if let efficiency = metrics.today?.efficiency, efficiency > 0 { return efficiency }
        if let efficiency = metrics.lastNight?.efficiency, efficiency > 0 { return efficiency }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()

                Group {
                    if metrics.isRefreshing && metrics.today == nil && metrics.lastNight == nil {
                        loadingView
                    } else {
                        scrollContent
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAlarm) {
                AlarmView()
                    .environmentObject(live)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await refreshDashboard()
        }
        .refreshable {
            await refreshDashboard()
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: WH.Spacing.md) {
            ProgressView()
                .tint(WH.Color.textSecondary)
            Text("Loading metrics...")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Main

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: WH.Spacing.md) {
                dashboardHeader
                progressRingRow
                aiInsightsCard
                monitorCards
                myDayHeader
                dailyOutlookRow
                todaysActivitiesCard
                tonightsSleepCard
                TodayAgendaView()

                if let err = metrics.lastError {
                    errorBanner(err)
                }

                localProcessingBanner

                if metrics.today == nil && metrics.lastNight == nil && !metrics.isRefreshing {
                    emptyState
                }

                statusFooter
            }
            .padding(.horizontal, WH.Spacing.md)
            .padding(.top, WH.Spacing.sm)
            .padding(.bottom, WH.Spacing.xxl)
        }
        .background(Color.clear)
    }

    private var dashboardHeader: some View {
        VStack(spacing: 12) {
            DashboardDatePill()

            Text("OpenWhoop")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(3.0)
                .textCase(.uppercase)

            if live.state.connected {
                liveStatusStrip
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var liveStatusStrip: some View {
        HStack(spacing: WH.Spacing.sm) {
            if let hr = live.state.heartRate {
                HeaderChip(icon: "heart.fill", value: "\(hr)", unit: "bpm", tint: WH.Color.recoveryRed)
            }

            if let battery = live.state.batteryPct {
                HeaderChip(icon: batteryIcon(for: battery),
                           value: "\(Int(battery.rounded()))",
                           unit: "%",
                           tint: battery > 30 ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
            }
        }
    }

    private var progressRingRow: some View {
        HStack(alignment: .top, spacing: WH.Spacing.sm) {
            NavigationLink(destination: SleepPerformanceDetailView()) {
                DashboardProgressRing(
                    progress: sleepProgress,
                    value: sleepMinutes.map(formatSleepMinutesCompact) ?? "-",
                    label: "Sleep",
                    tint: Color(hex: "#5A98D6"),
                    trackTint: Color(hex: "#1A2633")
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: RecoveryDetailView()) {
                DashboardProgressRing(
                    progress: (recoveryPercent ?? 0) / 100,
                    value: recoveryPercent.map { "\(Int($0.rounded()))%" } ?? "-",
                    label: "Recovery",
                    tint: recoveryPercent.map(recoveryColor) ?? Color(hex: "#E5DE55"),
                    trackTint: Color(hex: "#33321A"),
                    size: 110,
                    strokeWidth: 10
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: StrainDetailView()) {
                DashboardProgressRing(
                    progress: min(1, max(0, (strainValue ?? 0) / 21)),
                    value: strainValue.map { String(format: "%.1f", $0) } ?? "-",
                    label: "Strain",
                    tint: Color(hex: "#4E8BCA"),
                    trackTint: Color(hex: "#152336")
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, WH.Spacing.sm)
        .padding(.bottom, WH.Spacing.sm)
    }

    private var aiInsightsCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AI INSIGHTS")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.3)
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "#E5DE55"))
                }

                Text(insightCopy)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WH.Color.textPrimary.opacity(0.82))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var monitorCards: some View {
        HStack(spacing: WH.Spacing.sm) {
            MonitorMiniCard(
                title: "Health\nMonitor",
                value: healthMonitorStatus.value,
                detail: healthMonitorStatus.detail,
                icon: healthMonitorStatus.icon,
                tint: healthMonitorStatus.tint
            )

            MonitorMiniCard(
                title: "Stress\nMonitor",
                value: "Pending",
                detail: "Not enough data",
                icon: "waveform.path.ecg",
                tint: WH.Color.teal
            )
        }
    }

    private var myDayHeader: some View {
        HStack {
            Text("My Day")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)

            Spacer()

            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WH.Color.textSecondary)
                .opacity(0.55)
                .accessibilityHidden(true)
        }
        .padding(.top, WH.Spacing.sm)
        .padding(.horizontal, 4)
    }

    private var dailyOutlookRow: some View {
        DashboardCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sun.max")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
                    .frame(width: 24)

                Text("Your Daily Outlook")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WH.Color.textPrimary.opacity(0.9))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.75))
            }
        }
    }

    private var todaysActivitiesCard: some View {
        DashboardCard(padding: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: WH.Spacing.md) {
                    HStack {
                        Text("TODAY'S ACTIVITIES")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(WH.Color.textSecondary)
                            .tracking(1.2)

                        Spacer()

                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WH.Color.textSecondary.opacity(0.75))
                    }

                    if let sleepMinutes {
                        activityRow(
                            icon: "moon.fill",
                            iconTint: Color(hex: "#5A98D6"),
                            value: formatSleepMinutesClock(sleepMinutes),
                            label: "Sleep",
                            detail: sleepWindowText
                        )
                    }

                    if let workout = workoutManager.recentCompletedSessions.first {
                        activityRow(
                            icon: workout.type.iconName,
                            iconTint: WH.Color.strainBlue,
                            value: formatWorkoutDuration(workout.duration),
                            label: workout.type.displayName,
                            detail: workoutDetailText(workout)
                        )
                    } else if sleepMinutes == nil {
                        noActivityRow
                    }
                }
                .padding(WH.Spacing.md)

                Divider()
                    .overlay(Color(hex: "#2A2D33"))

                HStack(spacing: 0) {
                    dashboardActionButton("ADD ACTIVITY", icon: "plus")
                    Divider()
                        .frame(height: 44)
                        .overlay(Color(hex: "#2A2D33"))
                    dashboardActionButton("START ACTIVITY", icon: "circle")
                }
                .opacity(0.82)
            }
        }
    }

    private var tonightsSleepCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: WH.Spacing.md) {
                HStack {
                    Text("TONIGHT'S SLEEP")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.75))
                }

                HStack(alignment: .center, spacing: WH.Spacing.md) {
                    sleepPlanMetric(icon: "moon.fill",
                                    title: "Recommended\nBedtime",
                                    value: recommendedBedtimeText,
                                    tint: WH.Color.textPrimary.opacity(0.86))

                    DashedDivider()

                    sleepPlanMetric(icon: "sun.max.fill",
                                    title: alarmEnabled ? "Alarm On" : "Alarm Off",
                                    value: alarmTimeString,
                                    tint: Color(hex: "#E5DE55"))
                }

                Button {
                    showingAlarm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                        Text("SET ALARM")
                    }
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WH.Color.textPrimary)
                    .tracking(1.1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(hex: "#2A2D33"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noActivityRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .frame(width: 34, height: 34)
                .background(Color(hex: "#15171B"), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("No activities yet")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary.opacity(0.9))
                Text(metrics.today?.exerciseCount.map { "\($0) detected today" } ?? "Workouts are detected automatically")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            }

            Spacer()
        }
    }

    private func activityRow(icon: String, iconTint: Color, value: String, label: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(iconTint)
                .frame(width: 34, height: 34)
                .background(iconTint.opacity(0.15), in: Circle())

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(label.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WH.Color.textSecondary)
                    .tracking(1.4)
            }

            Spacer(minLength: WH.Spacing.sm)

            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func dashboardActionButton(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(1.0)
        }
        .foregroundStyle(WH.Color.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    private func sleepPlanMetric(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(tint)

            Text(title.uppercased())
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(title == "Alarm Off" ? Color(hex: "#E5DE55") : WH.Color.textSecondary)
                .tracking(1.1)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: States

    private var emptyState: some View {
        DashboardCard {
            VStack(spacing: WH.Spacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
                Text("No metrics yet")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text("Pull down to refresh")
                    .font(WH.Font.caption)
                    .foregroundStyle(WH.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var statusFooter: some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: metrics.isRefreshing ? "arrow.triangle.2.circlepath" : "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)

            Text(metrics.isRefreshing ? "Updating dashboard..." : "Updated \(refreshText)")
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)

            Spacer()
        }
        .padding(.horizontal, WH.Spacing.xs)
    }

    private var localProcessingBanner: some View {
        Group {
            if !serverDiagnostics.serverAvailable {
                HStack(spacing: WH.Spacing.sm) {
                    Image(systemName: "cpu")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WH.Color.recoveryGreen)
                    Text(serverDiagnostics.localProcessingSummary)
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                    Spacer()
                }
                .padding(WH.Spacing.sm)
                .background(WH.Color.surface2, in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WH.Color.recoveryYellow)
            Text(message)
                .font(WH.Font.caption)
                .foregroundStyle(WH.Color.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(WH.Spacing.sm)
        .background(WH.Color.surface2, in: RoundedRectangle(cornerRadius: WH.Radius.chip, style: .continuous))
    }

    private func refreshDashboard() async {
        await metrics.refresh()
        recoveryScore = await metrics.recoveryScore()
        await workoutManager.load()
    }

    // MARK: Copy and formatting

    private var insightCopy: String {
        if recoveryScore?.zone == .buildingBaseline {
            return "Recovery is building your baseline from valid nights before it starts scoring readiness."
        }
        if let recoveryPercent {
            switch recoveryPercent {
            case 67...:
                return "Your recovery is trending strong. This is a good day to build strain if your schedule allows."
            case 34..<67:
                return "Your recovery is in a balanced range. Keep an eye on strain and prioritize steady pacing."
            default:
                return "Your recovery is low today. Consider lighter activity, hydration, and an earlier wind-down."
            }
        }
        return "Your recovery and HRV trends will appear here once insights are available."
    }

    private var healthMonitorStatus: (value: String, detail: String, icon: String, tint: Color) {
        let available = [
            hrvValue.map { _ in true },
            rhrValue.map { _ in true },
            metrics.today?.spo2Pct.map { _ in true },
            metrics.today?.skinTempDevC.map { _ in true },
            metrics.today?.respRateBpm.map { _ in true }
        ].compactMap { $0 }.count

        guard available > 0 else {
            return ("Pending", "Awaiting metrics", "circle", WH.Color.textSecondary)
        }

        let value = available >= 4 ? "Within\nRange" : "Partial\nData"
        return (value, "\(available)/5 metrics", "checkmark", available >= 4 ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
    }

    private var sleepProgress: Double {
        min(1, max(0, (sleepMinutes ?? 0) / (8 * 60)))
    }

    private var sleepWindowText: String {
        guard let session = metrics.lastNight else {
            return sleepEfficiency.map { "\(Int(($0 * 100).rounded()))% efficiency" } ?? "Last night"
        }
        return "\(formatTime(session.startTs))\n\(formatTime(session.endTs))"
    }

    private var recommendedBedtimeText: String {
        guard let wakeDate = nextWakeDate else { return "--" }
        let bedtime = wakeDate.addingTimeInterval(-8 * 60 * 60)
        return Self.shortTimeFormatter.string(from: bedtime)
    }

    private var alarmTimeString: String {
        guard let wakeDate = nextWakeDate else { return "--" }
        return Self.shortTimeFormatter.string(from: wakeDate)
    }

    private var nextWakeDate: Date? {
        Calendar.current.date(bySettingHour: wakeByHour, minute: wakeByMinute, second: 0, of: Date())
    }

    private var refreshText: String {
        if metrics.isRefreshing { return "updating" }
        if let at = metrics.lastRefreshedAt { return relativeTime(from: at) }
        return "not synced"
    }

    private func recoveryColor(_ percent: Double) -> Color {
        WH.Color.recoveryColor(forPercent: percent)
    }

    private func batteryIcon(for pct: Double) -> String {
        switch pct {
        case 70...: return "battery.100"
        case 30..<70: return "battery.50"
        default: return "battery.25"
        }
    }

    private func formatSleepMinutes(_ totalMin: Double) -> String {
        guard totalMin > 0 else { return "-" }
        let hours = Int(totalMin) / 60
        let mins = Int(totalMin) % 60
        if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(mins)m"
    }

    private func formatSleepMinutesCompact(_ totalMin: Double) -> String {
        guard totalMin > 0 else { return "-" }
        let hours = Int(totalMin) / 60
        let mins = Int(totalMin) % 60
        return "\(hours):" + String(format: "%02d", mins)
    }

    private func formatSleepMinutesClock(_ totalMin: Double) -> String {
        formatSleepMinutesCompact(totalMin)
    }

    private func formatWorkoutDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours):" + String(format: "%02d", minutes) }
        return "\(minutes)m"
    }

    private func workoutDetailText(_ workout: WorkoutSession) -> String {
        let time = Self.shortTimeFormatter.string(from: workout.startTime)
        if workout.strainScore > 0 {
            let confidence = workout.isStrengthWorkout && workout.userIntensity == nil ? "\nDefault intensity" : ""
            return "\(time)\n\(String(format: "%.1f", workout.strainScore)) strain\(confidence)"
        }
        if let averageHeartRate = workout.averageHeartRate {
            return "\(time)\n\(Int(averageHeartRate.rounded())) bpm avg"
        }
        return "\(time)\nTracked workout"
    }

    private func formatTime(_ ts: Int) -> String {
        Self.shortTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private func relativeTime(from date: Date) -> String {
        let elapsed = Int(-date.timeIntervalSinceNow)
        switch elapsed {
        case ..<5:
            return "just now"
        case ..<60:
            return "\(elapsed)s ago"
        case ..<3600:
            return "\(elapsed / 60)m ago"
        default:
            return "\(elapsed / 3600)h ago"
        }
    }

    private static let shortTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        fmt.amSymbol = "AM"
        fmt.pmSymbol = "PM"
        return fmt
    }()
}

// MARK: - Dashboard Components

private struct DashboardBackground: View {
    var body: some View {
        ZStack {
            Color(hex: "#090A0C").ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(hex: "#152336").opacity(0.7),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(hex: "#1C1E22").opacity(0.9),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 60,
                endRadius: 360
            )
            .ignoresSafeArea()
        }
    }
}

private struct HeaderChip: View {
    let icon: String
    let value: String
    let unit: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(hex: "#1E2024"), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(hex: "#2A2D33"), lineWidth: 1)
        }
    }
}

private struct DashedDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                    }
                    .stroke(Color(hex: "#5F646D").opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
            }
            .frame(maxWidth: .infinity)
    }
}

#Preview("Today - empty (cold start)") {
    let metrics = MetricsRepository(deviceId: "preview")
    let live = LiveViewModel(deviceId: "preview")
    let steps = StepCountingService()
    TodayView()
        .environmentObject(metrics)
        .environmentObject(live)
        .environmentObject(steps)
        .environmentObject(WorkoutManager(deviceId: "preview", metrics: metrics, liveState: live.state))
        .environmentObject(ServerDiagnostics.shared)
}
