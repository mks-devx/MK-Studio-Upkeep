// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

struct FormatBadges: View {
    let formats: Set<PluginFormat>
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(PluginFormat.allCases.filter { formats.contains($0) }, id: \.self) { format in
                Text(format == .audioUnit ? "AU" : format.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(format))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(color(format).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel(format.rawValue)
            }
        }
    }
    private func color(_ format: PluginFormat) -> Color {
        switch format {
        case .audioUnit: .blue
        case .vst2: .orange
        case .vst3: .purple
        case .clap: .teal
        }
    }
}
