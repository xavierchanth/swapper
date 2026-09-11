import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            WindowMoverSettingsView()
                .tabItem {
                    Label("Window Mover", systemImage: "rectangle.on.rectangle")
                }

            HyperSettingsView()
                .tabItem { Label("Hyper", systemImage: "keyboard") }

            MenuBarHidingSettingsView()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            #if XMT_VOICE
            VoiceSettingsView()
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                }
            #endif
        }
        .frame(width: 620, height: 560)
        .padding(20)
    }
}
