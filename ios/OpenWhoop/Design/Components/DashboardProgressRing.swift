import SwiftUI

struct DashboardProgressRing: View {
    let progress: Double
    let value: String
    let label: String
    let tint: Color
    var trackTint: Color = Color(hex: "#1A2633")
    var size: CGFloat = 96
    var strokeWidth: CGFloat = 8

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(trackTint, lineWidth: strokeWidth)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.7), value: clampedProgress)

                Text(value)
                    .font(.system(size: size * 0.22, weight: .black, design: .rounded))
                    .foregroundStyle(WH.Color.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: size, height: size)

            HStack(spacing: 3) {
                Text(label.uppercased())
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .black))
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(WH.Color.textSecondary)
            .tracking(1.2)
        }
        .frame(maxWidth: .infinity)
    }
}

