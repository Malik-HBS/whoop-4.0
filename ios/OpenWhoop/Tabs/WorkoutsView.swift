import SwiftUI

struct WorkoutsView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @EnvironmentObject private var live: LiveViewModel

    @State private var presentedSheet: WorkoutSheet?
    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: WH.Spacing.md) {
                        ScreenHeader("Workouts")
                        introCard

                        if let activeSession = workoutManager.activeSession {
                            activeWorkoutBanner(activeSession)
                        }

                        workoutPicker
                        recentWorkoutsSection
                    }
                    .padding(.bottom, WH.Spacing.xxl)
                }
                .background(WH.Color.background)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .active(let sessionID):
                    if let session = workoutManager.session(id: sessionID) {
                        ActiveWorkoutView(session: session) { completedID in
                            presentedSheet = .summary(completedID)
                        }
                        .environmentObject(workoutManager)
                        .environmentObject(live)
                    }
                case .summary(let sessionID):
                    if let session = workoutManager.session(id: sessionID) {
                        WorkoutSummaryView(session: session, isEditable: true) {
                            workoutManager.dismissSummary()
                            presentedSheet = nil
                        }
                        .environmentObject(workoutManager)
                    }
                }
            }
            .onAppear {
                if let activeSession = workoutManager.activeSession {
                    presentedSheet = .active(activeSession.id)
                }
            }
            .onChange(of: workoutManager.lastCompletedSessionID) { completedID in
                guard let completedID else { return }
                presentedSheet = .summary(completedID)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.xs) {
            Text("Workout")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Text("Start a workout to track strain more accurately.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
            if let summary = workoutManager.todaysSummary {
                HStack(spacing: WH.Spacing.sm) {
                    statPill(title: "Today's strain", value: String(format: "%.1f", summary.score))
                    statPill(title: "Workouts", value: "\(summary.workoutCount)")
                }
                .padding(.top, WH.Spacing.xs)
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .padding(.horizontal, WH.Spacing.md)
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WH.Color.surface2, in: Capsule())
    }

    private func activeWorkoutBanner(_ session: WorkoutSession) -> some View {
        Button {
            presentedSheet = .active(session.id)
        } label: {
            HStack(spacing: WH.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTIVE WORKOUT")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)
                    Text(session.type.displayName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text("\(formatDuration(session.duration)) · \(session.averageHeartRate.map { "\(Int($0.rounded())) bpm avg" } ?? "Waiting for HR")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WH.Color.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.1f", session.strainScore))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(WH.Color.strainBlue)
                        .monospacedDigit()
                    Text("strain")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
            .padding(WH.Spacing.md)
            .background(
                LinearGradient(colors: [WH.Color.surface, WH.Color.surface2],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
                    .stroke(WH.Color.strainBlue.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, WH.Spacing.md)
    }

    private var workoutPicker: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("Start Workout")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.4)
                .padding(.horizontal, WH.Spacing.md)

            ForEach(WorkoutType.allCases) { type in
                Button {
                    workoutManager.startWorkout(type: type)
                    if let activeSession = workoutManager.activeSession {
                        presentedSheet = .active(activeSession.id)
                    }
                } label: {
                    workoutCard(for: type)
                }
                .buttonStyle(.plain)
                .disabled(workoutManager.activeSession != nil)
                .opacity(workoutManager.activeSession == nil ? 1 : 0.58)
                .padding(.horizontal, WH.Spacing.md)
            }
        }
    }

    private func workoutCard(for type: WorkoutType) -> some View {
        HStack(spacing: WH.Spacing.md) {
            ZStack {
                Circle()
                    .fill(WH.Color.surface2)
                    .frame(width: 52, height: 52)
                Image(systemName: type.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WH.Color.strainBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(type.displayName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text(type.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.8))
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("Recent Workouts")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.4)
                .padding(.horizontal, WH.Spacing.md)

            if workoutManager.recentCompletedSessions.isEmpty {
                VStack(spacing: WH.Spacing.sm) {
                    Image(systemName: "figure.mixed.cardio")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(WH.Color.textSecondary)
                    Text("No manual workouts yet")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text("Manual sessions you start here will drive workout strain and your daily strain total.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WH.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, WH.Spacing.lg)
                .padding(.vertical, WH.Spacing.xl)
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
                .padding(.horizontal, WH.Spacing.md)
            } else {
                VStack(spacing: 1) {
                    ForEach(workoutManager.recentCompletedSessions) { session in
                        NavigationLink {
                            WorkoutSummaryView(session: session, isEditable: false)
                                .environmentObject(workoutManager)
                        } label: {
                            recentWorkoutRow(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(WH.Color.surface,
                            in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
                .padding(.horizontal, WH.Spacing.md)
            }
        }
    }

    private func recentWorkoutRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: session.type.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WH.Color.strainBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.type.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                Text("\(rowDate(session.startTime)) · \(formatDuration(session.duration))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.1f", session.strainScore))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(WH.Color.strainBlue)
                    .monospacedDigit()
                Text(session.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "No HR")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, WH.Spacing.md)
        .padding(.vertical, WH.Spacing.sm)
    }

    private func rowDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private enum WorkoutSheet: Identifiable {
    case active(UUID)
    case summary(UUID)

    var id: String {
        switch self {
        case .active(let id): return "active-\(id.uuidString)"
        case .summary(let id): return "summary-\(id.uuidString)"
        }
    }
}

private struct ActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutManager: WorkoutManager
    @EnvironmentObject private var live: LiveViewModel

    let session: WorkoutSession
    let onEnded: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: WH.Spacing.md) {
                        titleCard
                        statsGrid
                        if let currentZone = workoutManager.session(id: session.id)?.zoneBreakdown.currentZone {
                            zoneCard(currentZone: currentZone)
                        }
                        actionCard
                    }
                    .padding(WH.Spacing.md)
                }
            }
            .navigationTitle(session.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(WH.Color.textPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var latestSession: WorkoutSession {
        workoutManager.session(id: session.id) ?? session
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text(latestSession.type.displayName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            HStack(spacing: WH.Spacing.sm) {
                activeBadge(live.state.connected ? "Connected" : "Waiting", tint: live.state.connected ? WH.Color.recoveryGreen : WH.Color.recoveryYellow)
                if let hr = live.state.heartRate {
                    activeBadge("\(hr) bpm", tint: WH.Color.recoveryRed)
                }
            }
            Text("Current strain estimate updates throughout the workout and will be finalized when you end the session.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func activeBadge(_ value: String, tint: Color) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private var statsGrid: some View {
        let current = latestSession
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: WH.Spacing.sm) {
            metricTile("Timer", value: formatDuration(current.duration), tone: WH.Color.textPrimary)
            metricTile("Current HR", value: live.state.heartRate.map { "\($0)" } ?? "—", suffix: live.state.heartRate != nil ? "bpm" : nil, tone: WH.Color.recoveryRed)
            metricTile("Average HR", value: current.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—", suffix: current.averageHeartRate != nil ? "bpm" : nil, tone: WH.Color.textPrimary)
            metricTile("Max HR", value: current.maxHeartRate.map { "\(Int($0.rounded()))" } ?? "—", suffix: current.maxHeartRate != nil ? "bpm" : nil, tone: WH.Color.recoveryYellow)
            metricTile("Strain", value: String(format: "%.1f", current.strainScore), suffix: "/ 21", tone: WH.Color.strainBlue)
            metricTile("Load", value: String(format: "%.0f", current.totalLoad), tone: WH.Color.textPrimary)
        }
    }

    private func metricTile(_ label: String, value: String, suffix: String? = nil, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(tone)
                    .monospacedDigit()
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func zoneCard(currentZone: Int) -> some View {
        let percentages = latestSession.zoneBreakdown.percentages
        return VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("Heart Rate Zones")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)

            HStack {
                ForEach(0..<6, id: \.self) { zone in
                    VStack(spacing: 6) {
                        Text("Z\(zone)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(zone == currentZone ? WH.Color.strainBlue : WH.Color.textSecondary)
                        Text(String(format: "%.0f%%", percentages[zone] ?? 0))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(WH.Color.textPrimary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("Workout control")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
            Button(role: .destructive) {
                Task {
                    if let finished = await workoutManager.endActiveWorkout() {
                        onEnded(finished.id)
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    Text("End Workout")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(WH.Color.recoveryRed, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutManager: WorkoutManager

    let session: WorkoutSession
    let isEditable: Bool
    var onDone: (() -> Void)? = nil

    @State private var selectedIntensity: Int?

    var body: some View {
        let current = workoutManager.session(id: session.id) ?? session

        NavigationStack {
            ZStack {
                WH.Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: WH.Spacing.md) {
                        summaryHero(current)
                        loadBreakdown(current)
                        if current.isStrengthWorkout {
                            strengthIntensityCard(current)
                        }
                    }
                    .padding(WH.Spacing.md)
                }
            }
            .navigationTitle("Workout Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditable ? "Save" : "Done") {
                        onDone?()
                        dismiss()
                    }
                    .foregroundStyle(WH.Color.textPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            selectedIntensity = session.userIntensity
        }
    }

    private func summaryHero(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text(session.type.displayName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            HStack(spacing: WH.Spacing.sm) {
                summaryPill("Duration", value: formatDuration(session.duration))
                summaryPill("Avg HR", value: session.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—")
                summaryPill("Max HR", value: session.maxHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—")
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(String(format: "%.1f / 21 strain", session.strainScore))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.strainBlue)
                .monospacedDigit()
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func summaryPill(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WH.Color.surface2, in: Capsule())
    }

    private func loadBreakdown(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            Text("Load Breakdown")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WH.Color.textSecondary)
                .tracking(1.2)
            statRow("Estimated cardio load", value: String(format: "%.1f", session.cardioLoad))
            statRow("Estimated muscular load", value: String(format: "%.1f", session.muscularLoad))
            statRow("Daily stress accumulation", value: String(format: "%.1f", session.dailyStressLoad))
            statRow("Recovery adjustment", value: String(format: "%.2fx", session.recoveryAdjustment))
            statRow("Total workout load", value: String(format: "%.1f", session.totalLoad), accent: WH.Color.strainBlue)
            if let baseline = session.baselineStrain {
                statRow("Baseline strain anchor", value: String(format: "%.1f", baseline))
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func statRow(_ title: String, value: String, accent: Color = WH.Color.textPrimary) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
    }

    private func strengthIntensityCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: WH.Spacing.md) {
            Text("How intense was this strength workout?")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
            Text("You can skip this, but adding an intensity helps estimate muscular strain more accurately.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                ForEach(1...10, id: \.self) { level in
                    Button {
                        selectedIntensity = level
                        Task { await workoutManager.setStrengthIntensity(level, for: session.id) }
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(level)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text(intensityLabel(level))
                                .font(.system(size: 10, weight: .semibold))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .foregroundStyle((selectedIntensity ?? session.userIntensity) == level ? Color.white : WH.Color.textPrimary)
                        .background(
                            ((selectedIntensity ?? session.userIntensity) == level ? WH.Color.strainBlue : WH.Color.surface2),
                            in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEditable)
                }
            }

            if isEditable {
                Button {
                    selectedIntensity = nil
                    Task { await workoutManager.setStrengthIntensity(nil, for: session.id) }
                } label: {
                    Text("Use default intensity (5)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text("Muscular strain confidence: \(Int((session.muscularConfidence * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }

    private func intensityLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Very easy"
        case 2: return "Easy"
        case 3: return "Light"
        case 4: return "Moderate-light"
        case 5: return "Moderate"
        case 6: return "Challenging"
        case 7: return "Hard"
        case 8: return "Very hard"
        case 9: return "Extremely hard"
        default: return "Max effort"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview("Workouts") {
    let metrics = MetricsRepository(deviceId: "preview")
    let live = LiveViewModel(deviceId: "preview")
    WorkoutsView()
        .environmentObject(metrics)
        .environmentObject(live)
        .environmentObject(WorkoutManager(deviceId: "preview", metrics: metrics, liveState: live.state))
}
