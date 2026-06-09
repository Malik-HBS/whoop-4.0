import SwiftUI

struct DashboardCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = WH.Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: "#1C1E22"))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(hex: "#2A2D33"), lineWidth: 1)
            }
    }
}

