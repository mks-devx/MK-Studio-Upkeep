// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

/// Each disclosure remains manually adjustable; changing the preference updates open views.
struct TechnicalDetailsDisclosure<Content: View>: View {
    @AppStorage(StudioUpkeepPreference.expandTechnicalDetails) private var preferredExpansion = false
    @State private var expanded = false
    @ViewBuilder let content: Content

    var body: some View {
        DisclosureGroup("Technical details", isExpanded: $expanded) { content }
            .onAppear { expanded = preferredExpansion }
            .onChange(of: preferredExpansion) { expanded = $0 }
    }
}
