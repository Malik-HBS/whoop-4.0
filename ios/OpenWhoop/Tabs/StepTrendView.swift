import SwiftUI
import Charts

struct StepTrendView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var steps: StepCountingService

    @State private var range: StepTrendRange = .month
    @State private var periodOffset = 0
    @State private var summaries: [DailyStepSummary] = []
    @State private var comparisonSummaries: [DailyStepSummary] = []
    @State private var showingGoalEditor = false

    private var points: [StepTrendPoint] {
        summaries.map { StepTrendPoint(summary: $0) }
    }

    private var averageSteps: Int {
        guard !summaries.isEmpty else { return 0 }
        return summaries.reduce(0) { $0 + $1.totalSteps } / summaries.count
    }

    private var priorAverageSteps: Int {
        guard !comparisonSummaries.isEmpty else { return 0 }
        return comparisonSummaries.reduce(0) { $0 + $1.totalSteps } / comparisonSummaries.count
    }

    private var deltaPercent: Int? {
        guard priorAverageSteps > 0 else { return nil }
        return Int(((Double(averageSteps) - Double(priorAverageSteps)) / Double(priorAverageSteps) * 100).rounded())
    }

    private var yDomain: ClosedRange<Double> {
        let maxValue = max(points.map(\.steps).max() ?? 0, steps.state.dailyGoal, averageSteps, 5_000)
        let top = Double(((maxValue + 4_999) / 5_000) * 5_000)
        return 0...max(top, 10_000)
    }

    var body: some View {
        ZStack {
            StepTrendBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    metricSelector
                    summarySection
                    chartSection
                    goalCard
                }
                .padding(.horizontal, WH.Spacing.md)
                .padding(.top, WH.Spacing.sm)
                .padding(.bottom, WH.Spacing.xxl)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { reload() }
        .onChange(of: range) { _ in
            periodOffset = 0
            reload()
        }
        .sheet(isPresented: $showingGoalEditor) {
            StepGoalEditor(goal: steps.state.dailyGoal) { newGoal in
                steps.setDailyGoal(newGoal)
                reload()
            }
        }
    }

    private var header: some View {
        ZStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(WH.Color.textPrimary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("TREND VIEW")
                .font(.system(size: 16, weight: .black))
                .tracking(3.0)
                .foregroundStyle(WH.Color.textPrimary)
        }
    }

    private var metricSelector: some View {
        DashboardCard(padding: 18) {
            HStack(spacing: 16) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
                    .frame(width: 36)

                Text("STEPS")
                    .font(.system(size: 18, weight: .black))
                    .tracking(2.2)
                    .foregroundStyle(WH.Color.textPrimary)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WH.Color.textPrimary)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AVERAGE")
                        .font(.system(size: 14, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(WH.Color.textSecondary)
                    Text(averageSteps.formatted())
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()

                    if let deltaPercent {
                        deltaPill(deltaPercent)
                    }
                }

                Spacer()

                Picker("Range", selection: $range) {
                    ForEach(StepTrendRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .tint(WH.Color.surface2)
            }

            HStack {
                Button {
                    shiftRange(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(WH.Color.textPrimary)
                }

                Spacer()

                Text(dateRangeText)
                    .font(.system(size: 16, weight: .black))
                    .tracking(1.6)
                    .foregroundStyle(WH.Color.textPrimary)

                Spacer()

                Button {
                    shiftRange(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(periodOffset == 0 ? WH.Color.textSecondary.opacity(0.45) : WH.Color.textPrimary)
                }
                .disabled(periodOffset == 0)
            }

            Text(insightText)
                .font(.system(size: 17, weight: .semibold))
                .lineSpacing(4)
                .foregroundStyle(WH.Color.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chartSection: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Day", point.date),
                    y: .value("Steps", point.steps),
                    width: range.barWidth
                )
                .foregroundStyle(Color(hex: "#16A7F2"))
                .cornerRadius(3)
            }

            RuleMark(y: .value("Average", averageSteps))
                .foregroundStyle(WH.Color.textPrimary.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))
                .annotation(position: .leading, alignment: .center) {
                    Text("AVG.")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

            RuleMark(y: .value("Goal", steps.state.dailyGoal))
                .foregroundStyle(Color(hex: "#7BD88F").opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range.axisTickCount)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(for: date))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                    .foregroundStyle(WH.Color.separator.opacity(0.7))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Int(number).formatted())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 330)
    }

    private var goalCard: some View {
        Button {
            showingGoalEditor = true
        } label: {
            DashboardCard(padding: 18) {
                HStack(spacing: 16) {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(WH.Color.textSecondary)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("UPDATE YOUR DAILY STEP GOAL")
                            .font(.system(size: 15, weight: .black))
                            .tracking(1.8)
                            .foregroundStyle(WH.Color.textPrimary)
                        Text("\(steps.state.dailyGoal.formatted()) steps")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WH.Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func deltaPill(_ delta: Int) -> some View {
        let positive = delta >= 0
        return Label("\(abs(delta))% vs. prior \(range.comparisonLabel)", systemImage: positive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(positive ? Color(hex: "#2DE2A0") : WH.Color.recoveryRed)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((positive ? Color(hex: "#143F34") : WH.Color.recoveryRed.opacity(0.16)), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var dateRangeText: String {
        guard let first = points.first?.date, let last = points.last?.date else { return "--" }
        return "\(Self.rangeFormatter.string(from: first).uppercased()) - \(Self.rangeFormatter.string(from: last).uppercased()), \(Self.yearFormatter.string(from: last))"
    }

    private var insightText: String {
        guard let deltaPercent else {
            return "Your step trend will build as daily movement data comes in."
        }
        if deltaPercent >= 0 {
            return "Your average steps are up from the prior \(range.comparisonLabel). Keep stacking small wins."
        }
        return "Your average steps are down from the prior \(range.comparisonLabel). A short walk can help close the gap."
    }

    private func axisLabel(for date: Date) -> String {
        range == .sixMonths ? Self.monthFormatter.string(from: date) : Self.axisFormatter.string(from: date)
    }

    private func shiftRange(_ direction: Int) {
        if direction < 0 {
            periodOffset += 1
        } else {
            periodOffset = max(0, periodOffset - 1)
        }
        reload()
    }

    private func reload() {
        let endDate = Calendar.current.date(byAdding: .day, value: -(periodOffset * range.days), to: Date()) ?? Date()
        summaries = steps.dailySummaries(endingAt: endDate, days: range.days)
        comparisonSummaries = steps.dailySummaries(endingAt: endDate, days: range.days * 2).prefix(range.days).map { $0 }
    }

    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy"
        return formatter
    }()

    private static let axisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM\nd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
}

private enum StepTrendRange: String, CaseIterable, Identifiable {
    case week
    case month
    case sixMonths

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "W"
        case .month: return "M"
        case .sixMonths: return "6M"
        }
    }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 180
        }
    }

    var comparisonLabel: String {
        switch self {
        case .week: return "week"
        case .month: return "month"
        case .sixMonths: return "6 months"
        }
    }

    var axisTickCount: Int {
        switch self {
        case .week: return 4
        case .month: return 5
        case .sixMonths: return 6
        }
    }

    var barWidth: MarkDimension {
        switch self {
        case .week: return .fixed(18)
        case .month: return .fixed(8)
        case .sixMonths: return .fixed(3)
        }
    }
}

private struct StepTrendPoint: Identifiable {
    let id: String
    let date: Date
    let steps: Int

    init(summary: DailyStepSummary) {
        id = summary.localDate
        date = Self.formatter.date(from: summary.localDate) ?? summary.lastUpdatedAt
        steps = summary.totalSteps
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct StepGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftGoal: Double
    let onSave: (Int) -> Void

    init(goal: Int, onSave: @escaping (Int) -> Void) {
        _draftGoal = State(initialValue: Double(goal))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Step Goal")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                    Text(Int(draftGoal).formatted())
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()
                }

                Slider(value: $draftGoal, in: 1_000...50_000, step: 500)
                    .tint(Color(hex: "#7BD88F"))

                Stepper("Goal \(Int(draftGoal).formatted()) steps", value: $draftGoal, in: 1_000...50_000, step: 500)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WH.Color.textPrimary)

                Spacer()
            }
            .padding(WH.Spacing.lg)
            .background(WH.Color.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Int(draftGoal))
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct StepTrendBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(hex: "#27323B"),
                Color(hex: "#11141A"),
                Color(hex: "#090B10")
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

#Preview("Step Trend") {
    NavigationStack {
        StepTrendView()
            .environmentObject(StepCountingService())
    }
}
