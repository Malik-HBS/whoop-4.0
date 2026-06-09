import SwiftUI

struct SleepPerformanceDetailView: View {
    @EnvironmentObject private var metrics: MetricsRepository
    @Environment(\.dismiss) private var dismiss

    @State private var result: SleepScoreResult?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            SleepPerformanceBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: WH.Spacing.lg) {
                    header
                    scoreRing
                    componentPanel
                    explanationCard
                    Spacer(minLength: WH.Spacing.xl)
                }
                .padding(.horizontal, WH.Spacing.md)
                .padding(.top, WH.Spacing.sm)
                .padding(.bottom, WH.Spacing.xxl)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task {
            await loadScore()
        }
        .refreshable {
            await loadScore(refreshMetrics: true)
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(WH.Color.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("TODAY")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(WH.Color.textPrimary)
                .tracking(2.8)

            Spacer()

            Image(systemName: "info.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(WH.Color.textSecondary)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private var scoreRing: some View {
        let score = result?.score
        let progress = Double(score ?? 0) / 100

        return ZStack {
            Circle()
                .stroke(Color(hex: "#33414C").opacity(0.8), lineWidth: 18)

            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(
                    scoreTint,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.7), value: progress)

            VStack(spacing: WH.Spacing.sm) {
                Text("OPENWHOOP")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(WH.Color.textSecondary.opacity(0.9))
                    .tracking(3.5)

                if isLoading {
                    ProgressView()
                        .tint(WH.Color.textSecondary)
                        .scaleEffect(1.1)
                } else if let score {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("\(score)")
                            .font(.system(size: 82, weight: .black, design: .rounded))
                            .foregroundStyle(WH.Color.textPrimary)
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(WH.Color.textPrimary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                } else {
                    Text(result?.status == .buildingBaseline ? "BASELINE" : "--")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(WH.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Text(result?.status == .buildingBaseline ? "BUILDING" : "SLEEP SCORE")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(WH.Color.textPrimary)
                    .tracking(2.2)
                    .multilineTextAlignment(.center)

                if let result, result.status == .buildingBaseline {
                    Text("\(result.baselineProgress)/\(result.requiredBaselineNights) NIGHTS")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(scoreTint)
                        .tracking(1.6)
                }
            }
            .padding(30)
        }
        .frame(maxWidth: 340)
        .aspectRatio(1, contentMode: .fit)
        .padding(.vertical, WH.Spacing.lg)
    }

    private var componentPanel: some View {
        VStack(spacing: 0) {
            if let components = result?.components {
                let rows = componentRows(for: components)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    componentRow(row)
                    if index < rows.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.12))
                            .padding(.leading, 52)
                    }
                }
                legend
                    .padding(.top, WH.Spacing.md)
            } else {
                VStack(spacing: WH.Spacing.sm) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(scoreTint)
                    Text(result?.explanation ?? "Loading sleep score")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WH.Color.textPrimary.opacity(0.9))
                        .multilineTextAlignment(.center)
                    if let result, result.status == .buildingBaseline {
                        Text("\(result.baselineProgress)/\(result.requiredBaselineNights) nights collected")
                            .font(WH.Font.caption)
                            .foregroundStyle(WH.Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, WH.Spacing.lg)
            }
        }
        .padding(WH.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "#1D2026").opacity(0.95))
        )
        .overlay(alignment: .top) {
            Triangle()
                .fill(Color(hex: "#1D2026"))
                .frame(width: 42, height: 24)
                .offset(y: -22)
        }
    }

    private func componentRow(_ row: ComponentRow) -> some View {
        HStack(spacing: WH.Spacing.sm) {
            Image(systemName: row.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(WH.Color.textSecondary)
                .frame(width: 34)

            Text(row.title)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WH.Color.textPrimary.opacity(0.88))
                .tracking(1.6)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: WH.Spacing.sm)

            SegmentIndicator(progress: row.progress, tint: row.tint)
                .frame(width: 96, height: 8)

            Text("\(Int(row.points.rounded()))/\(Int(row.maxPoints))")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(WH.Color.textPrimary)
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
        .frame(minHeight: 68)
    }

    private var legend: some View {
        HStack(spacing: WH.Spacing.md) {
            legendItem("Poor", color: Color(hex: "#F0A72E"))
            legendItem("Sufficient", color: WH.Color.textSecondary)
            legendItem("Optimal", color: WH.Color.teal)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, WH.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func legendItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 22, height: 5)
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WH.Color.textSecondary)
        }
    }

    private var explanationCard: some View {
        Text(result?.explanation ?? "Sleep score loads from your raw-derived sleep metrics.")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(WH.Color.textPrimary.opacity(0.95))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(WH.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#12151A"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [WH.Color.sleepPurple, WH.Color.teal],
                                       startPoint: .leading,
                                       endPoint: .trailing),
                        lineWidth: 1
                    )
            }
    }

    private var scoreTint: Color {
        guard let score = result?.score else { return Color(hex: "#8CB7D8") }
        switch score {
        case 80...100:
            return WH.Color.teal
        case 60..<80:
            return WH.Color.recoveryYellow
        default:
            return WH.Color.recoveryRed
        }
    }

    private func componentRows(for components: SleepScoreComponents) -> [ComponentRow] {
        [
            ComponentRow(title: "HOURS VS. NEEDED", icon: "moon.fill",
                         points: components.sleepNeedCompletion, maxPoints: 35),
            ComponentRow(title: "SLEEP CONSISTENCY", icon: "moon.zzz",
                         points: components.consistency, maxPoints: 10),
            ComponentRow(title: "SLEEP EFFICIENCY", icon: "chart.bar",
                         points: components.sleepEfficiency, maxPoints: 20),
            ComponentRow(title: "AWAKE + DISTURBANCES", icon: "bed.double.fill",
                         points: components.disturbances, maxPoints: 15),
            ComponentRow(title: "HR/HRV RECOVERY", icon: "heart.fill",
                         points: components.recovery, maxPoints: 15),
            ComponentRow(title: "REM/DEEP BALANCE", icon: "waveform.path.ecg",
                         points: components.architecture, maxPoints: 5)
        ]
    }

    private func loadScore(refreshMetrics: Bool = false) async {
        isLoading = true
        if refreshMetrics {
            await metrics.refresh()
        }
        result = await metrics.sleepScore()
        isLoading = false
    }
}

private struct ComponentRow: Identifiable {
    let title: String
    let icon: String
    let points: Double
    let maxPoints: Double

    var id: String { title }

    var progress: Double {
        min(1, max(0, points / maxPoints))
    }

    var tint: Color {
        switch progress {
        case 0.8...:
            return WH.Color.teal
        case 0.5..<0.8:
            return WH.Color.textSecondary
        default:
            return Color(hex: "#F0A72E")
        }
    }
}

private struct SegmentIndicator: View {
    let progress: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill(for: index))
                    .frame(height: 6)
            }
        }
    }

    private func fill(for index: Int) -> Color {
        let activeSegments = Int(ceil(min(1, max(0, progress)) * 3))
        return index < activeSegments ? tint : WH.Color.textSecondary.opacity(0.28)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SleepPerformanceBackground: View {
    var body: some View {
        ZStack {
            Color(hex: "#0A0D11").ignoresSafeArea()
            LinearGradient(colors: [Color(hex: "#26323E"), Color(hex: "#10151B"), Color(hex: "#080A0D")],
                           startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

#Preview("Sleep Performance Detail") {
    SleepPerformanceDetailView()
        .environmentObject(MetricsRepository(deviceId: "preview"))
}
