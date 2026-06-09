import SwiftUI

struct RecoveryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var metrics: MetricsRepository

    @State private var recovery: RecoveryScore?
    @State private var isLoading = true

    private var score: Int? { recovery?.score }
    private var accent: Color {
        guard let recovery else { return WH.Color.recoveryYellow }
        switch recovery.zone {
        case .green: return WH.Color.recoveryGreen
        case .yellow, .buildingBaseline: return WH.Color.recoveryYellow
        case .red: return WH.Color.recoveryRed
        case nil: return WH.Color.textSecondary
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#26313A"), WH.Color.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(WH.Color.textSecondary)
            } else {
                scrollContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WH.Color.textPrimary)
                }
            }

            ToolbarItem(placement: .principal) {
                Text("TODAY")
                    .font(.system(size: 17, weight: .black))
                    .tracking(2.4)
                    .foregroundStyle(WH.Color.textPrimary)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Image(systemName: "info.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WH.Color.textSecondary)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            recovery = await metrics.recoveryScore()
            isLoading = false
        }
        .refreshable {
            recovery = await metrics.recoveryScore()
        }
    }

    private var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: WH.Spacing.lg) {
                heroRing
                metricPanel
                explanationPanel
            }
            .padding(.horizontal, WH.Spacing.md)
            .padding(.bottom, WH.Spacing.xxl)
        }
    }

    private var heroRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 18)

            Circle()
                .trim(from: 0, to: min(1, max(0, Double(score ?? 0) / 100)))
                .stroke(accent, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(score == nil ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.7), value: score)

            VStack(spacing: 6) {
                Text("OPENWHOOP")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(WH.Color.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(score.map(String.init) ?? "-")
                        .font(.system(size: 68, weight: .black, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()
                    if score != nil {
                        Text("%")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(WH.Color.textPrimary)
                    }
                }
                Text(recovery?.statusText.uppercased() ?? "RECOVERY")
                    .font(.system(size: 15, weight: .black))
                    .tracking(2.2)
                    .foregroundStyle(WH.Color.textPrimary)
            }
        }
        .frame(width: 250, height: 250)
        .padding(.top, WH.Spacing.lg)
    }

    private var metricPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(metricRows.enumerated()), id: \.offset) { index, row in
                RecoveryMetricRow(row: row)
                if index < metricRows.count - 1 {
                    Rectangle()
                        .fill(WH.Color.separator)
                        .frame(height: 1)
                        .padding(.leading, 44)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "arrowtriangle.up.fill")
                    .foregroundStyle(WH.Color.recoveryGreen)
                Image(systemName: "arrowtriangle.down.fill")
                    .foregroundStyle(WH.Color.recoveryYellow)
                Text("Today vs. your baseline")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WH.Color.textPrimary)
                Spacer()
            }
            .padding(.top, WH.Spacing.md)
            .padding(.horizontal, WH.Spacing.md)
            .padding(.bottom, WH.Spacing.md)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, WH.Spacing.sm)
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface2.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var explanationPanel: some View {
        VStack(alignment: .leading, spacing: WH.Spacing.sm) {
            ForEach((recovery?.explanation ?? ["Recovery will appear after the main sleep session is available."]).prefix(4), id: \.self) { item in
                Text(item)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WH.Color.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WH.Spacing.md)
        .background(WH.Color.surface, in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous)
                .stroke(accent.opacity(0.55), lineWidth: 1)
        }
    }

    private var metricRows: [RecoveryMetricRow.Model] {
        guard let input = recovery?.inputSnapshot else { return [] }
        let baseline = recovery?.baselineSnapshot
        return [
            row(title: "Heart Rate Variability", icon: "waveform.path.ecg", value: input.hrvRmssd, baseline: baseline?.hrvBaseline, unit: "", decimals: 0, higherIsBetter: true),
            row(title: "Resting Heart Rate", icon: "heart", value: input.sleepingRHR, baseline: baseline?.rhrBaseline, unit: "", decimals: 0, higherIsBetter: false),
            row(title: "Respiratory Rate", icon: "lungs", value: input.respiratoryRate, baseline: baseline?.respiratoryRateBaseline, unit: "", decimals: 1, higherIsBetter: false),
            row(title: "Sleep Performance", icon: "moon", value: input.sleepScore, baseline: baseline?.sleepScoreBaseline, unit: "%", decimals: 0, higherIsBetter: true),
            row(title: "Skin Temperature", icon: "thermometer", value: input.skinTemp, baseline: baseline?.skinTempBaseline, unit: "C", decimals: 1, higherIsBetter: false),
            row(title: "SpO2", icon: "drop", value: input.spo2, baseline: baseline?.spo2Baseline, unit: "%", decimals: 0, higherIsBetter: true)
        ].filter { $0.valueText != "-" || $0.baselineText != nil }
    }

    private func row(
        title: String,
        icon: String,
        value: Double?,
        baseline: Double?,
        unit: String,
        decimals: Int,
        higherIsBetter: Bool
    ) -> RecoveryMetricRow.Model {
        let delta = value.flatMap { current in baseline.map { current - $0 } }
        let trend: RecoveryMetricRow.Trend
        if let delta, abs(delta) > 0.05 {
            let good = higherIsBetter ? delta > 0 : delta < 0
            trend = good ? .good : .watch
        } else {
            trend = .neutral
        }
        return RecoveryMetricRow.Model(
            title: title,
            icon: icon,
            valueText: format(value, decimals: decimals, unit: unit),
            baselineText: baseline.map { format($0, decimals: decimals, unit: unit) },
            trend: trend
        )
    }

    private func format(_ value: Double?, decimals: Int, unit: String) -> String {
        guard let value else { return "-" }
        let text = String(format: "%.\(decimals)f", value)
        return unit.isEmpty ? text : "\(text)\(unit)"
    }
}

private struct RecoveryMetricRow: View {
    enum Trend {
        case good
        case watch
        case neutral

        var icon: String {
            switch self {
            case .good: return "arrowtriangle.up.fill"
            case .watch: return "arrowtriangle.down.fill"
            case .neutral: return "minus"
            }
        }

        var color: Color {
            switch self {
            case .good: return WH.Color.recoveryGreen
            case .watch: return WH.Color.recoveryYellow
            case .neutral: return WH.Color.textSecondary
            }
        }
    }

    struct Model {
        let title: String
        let icon: String
        let valueText: String
        let baselineText: String?
        let trend: Trend
    }

    let row: Model

    var body: some View {
        HStack(spacing: WH.Spacing.md) {
            Image(systemName: row.icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .frame(width: 28)

            Text(row.title.uppercased())
                .font(.system(size: 13, weight: .black))
                .tracking(1.3)
                .foregroundStyle(WH.Color.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Spacer(minLength: WH.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.valueText)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .monospacedDigit()
                    Image(systemName: row.trend.icon)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(row.trend.color)
                }
                if let baselineText = row.baselineText {
                    Text(baselineText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(WH.Color.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, WH.Spacing.md)
    }
}
