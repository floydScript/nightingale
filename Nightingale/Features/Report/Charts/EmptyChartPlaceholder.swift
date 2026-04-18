import SwiftUI

struct EmptyChartPlaceholder: View {
    let label: String
    var body: some View {
        HStack {
            Spacer()
            Text(label)
                .foregroundStyle(Theme.textTertiary)
                .font(.footnote)
            Spacer()
        }
        .frame(height: 60)
    }
}
