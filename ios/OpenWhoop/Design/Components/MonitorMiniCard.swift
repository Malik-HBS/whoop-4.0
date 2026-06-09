import SwiftUI

struct MonitorMiniCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        DashboardCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(WH.Color.textSecondary)
                        .tracking(1.2)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WH.Color.textSecondary.opacity(0.75))
                }

                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 18, height: 18)
                        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.uppercased())
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(tint)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        Text(detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WH.Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }
}

