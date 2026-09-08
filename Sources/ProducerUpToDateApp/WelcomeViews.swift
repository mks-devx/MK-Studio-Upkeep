// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var showsSetup = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(
                alignment: .leading,
                spacing: StudioUpkeepDesign.Space.xLarge
            ) {
                Spacer()

                AppIconView(size: 104)

                VStack(
                    alignment: .leading,
                    spacing: StudioUpkeepDesign.Space.medium
                ) {
                    Text("Your studio software,\nunder control.")
                        .font(.system(size: 40, weight: .semibold))
                        .tracking(-0.8)
                    Text(
                        "See your installed plugins and DAWs, find developer websites, and review compatibility and uninstall options."
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 610, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    if onboardingComplete { model.startScan() } else { showsSetup = true }
                } label: {
                    Label("Scan This Mac", systemImage: "magnifyingglass")
                        .frame(minWidth: 150)
                }
                .studioProminentButtonStyle()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .sheet(isPresented: $showsSetup) { OnboardingView() }

                Spacer()
            }
            .padding(StudioUpkeepDesign.Space.hero)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(
                alignment: .leading,
                spacing: StudioUpkeepDesign.Space.xLarge
            ) {
                Text("BUILT FOR TRUST")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(BrandColor.accent)

                TrustStatement(
                    icon: "lock.shield",
                    title: "Read-only scanning",
                    detail: "Plugin code never runs during inventory."
                )
                TrustStatement(
                    icon: "checkmark.seal",
                    title: "Evidence before claims",
                    detail: "Select a product for installed file details and update options."
                )
                TrustStatement(
                    icon: "arrow.uturn.backward.circle",
                    title: "Recoverable cleanup",
                    detail: "Selected software bundles are reviewed before moving to Trash."
                )

                Divider()

                Text("AU  •  VST3  •  VST2  •  CLAP  •  DAWs")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(StudioUpkeepDesign.Space.xxLarge)
            .frame(width: 390, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .studioPanelBackground()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TrustStatement: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(BrandColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ScanningView: View {
    @EnvironmentObject private var model: AppModel
    let startedAt: Date

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 8) {
                Text("Scanning plugins and DAWs…")
                    .font(.title2.weight(.semibold))
                Text("Reading installed versions, formats, and processor support.")
                    .foregroundStyle(.secondary)
            }

            Button("Cancel Scan") {
                model.cancelScan()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanning plugins and DAWs")
    }
}

struct ScanFailureView: View {
    @EnvironmentObject private var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42))
                .foregroundStyle(StudioUpkeepDesign.warning)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("The scan could not finish")
                    .font(.title2.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            Button("Scan Again") {
                model.startScan()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
