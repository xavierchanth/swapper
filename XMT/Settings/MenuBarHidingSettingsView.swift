import SwiftUI

struct MenuBarHidingSettingsView: View {
    @ObservedObject private var settings = MenuBarHidingSettings.shared

    var body: some View {
        Form {
            Section("Menu Bar Hiding") {
                Toggle("Enable menu bar hiding", isOn: Binding(
                    get: { settings.isEnabled }, set: settings.setEnabled
                ))
                HStack {
                    Text("Hide after")
                    TextField("Seconds", value: Binding(
                        get: { settings.autoHideSeconds }, set: settings.setAutoHideSeconds
                    ), format: .number.precision(.fractionLength(0)))
                    .frame(width: 72)
                    Text("seconds")
                }
                .disabled(!settings.isEnabled)

                if settings.isCompetingAppRunning {
                    Label("Hidden Bar is running. Quit Hidden Bar before using XMT menu bar hiding.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if settings.placementCorrectionNeeded {
                    Label("The separator must be left of the arrow. Hold Command and drag │ immediately to the arrow’s left, then click the arrow again.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Set Up") {
                Text("Hold Command and drag menu bar items across the │ separator. Items to its left are hidden when the arrow is collapsed; items to its right stay visible.")
                Text("Click the arrow to expand or collapse. Right-click it for Settings or Quit. Expanded items hide automatically after the configured delay, unless the pointer or menu is using the menu bar.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { settings.refreshCompetingAppStatus() }
    }
}
