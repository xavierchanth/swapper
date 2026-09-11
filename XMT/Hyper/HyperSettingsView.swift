import ApplicationServices
import AppKit
import SwiftUI

struct HyperSettingsView: View {
    @ObservedObject private var controller = HyperController.shared
    @State private var enabled = false
    @State private var holdMilliseconds = 200

    var body: some View {
        Form {
            Section("Hyper Caps") {
                Toggle("Tap Caps for Escape; hold for Hyper", isOn: $enabled)
                Stepper("Hold threshold: \(holdMilliseconds) ms", value: $holdMilliseconds, in: 1...60_000, step: 10)
                TextField("Hold threshold (ms)", value: $holdMilliseconds, format: .number)
                    .accessibilityLabel("Hyper hold threshold in milliseconds")
                Text(statusText).foregroundStyle(.secondary)
                Button("Apply") {
                    var value = controller.configuration
                    value.enabled = enabled; value.holdMilliseconds = holdMilliseconds
                    Task { await controller.apply(value) }
                }
                Button("Restore 200 ms Default") { holdMilliseconds = 200 }
                Text("Uses the built-in keyboard. F18 is reserved internally across keyboards. Your existing Hyperkey app must be quit before enabling XMT Hyper.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Password fields can block keyboard interception. Hyper is unavailable there; if interrupted, reopen XMT to resume.")
                    .font(.caption).foregroundStyle(.secondary)
                if case .permissionRequired = controller.status {
                    Button("Request Accessibility Access") {
                        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    }
                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                    }
                }
                if case .recoveryRequired = controller.status {
                    Button("Retry Mapping Recovery") { Task { await controller.start() } }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(controller.isBusy)
        .onAppear { enabled = controller.configuration.enabled; holdMilliseconds = controller.configuration.holdMilliseconds }
    }

    private var statusText: String {
        switch controller.status {
        case .disabled: "Disabled — targets the built-in keyboard when enabled"
        case .enabling: "Enabling…"
        case .active(let keyboard): "Active on \(keyboard.displayName)"
        case .permissionRequired: "Accessibility permission is required"
        case .recoveryRequired: "Mapping recovery is required before quitting"
        case .suspended: "Suspended until XMT becomes active again"
        case .unavailable(let message): "Unavailable: \(message)"
        case .failed(let message): "Error: \(message)"
        }
    }
}
