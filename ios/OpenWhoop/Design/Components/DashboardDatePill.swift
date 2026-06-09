import SwiftUI

struct DashboardDatePill: View {
    var title: String = "TODAY"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left")
            Text(title)
                .font(.system(size: 12, weight: .black))
                .tracking(1.3)
            Image(systemName: "chevron.right")
        }
        .foregroundStyle(WH.Color.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(hex: "#1E2024"), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(hex: "#2A2D33"), lineWidth: 1)
        }
        .accessibilityLabel(title)
    }
}

