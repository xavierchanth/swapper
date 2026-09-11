import SwiftUI
import Darwin

@main
enum XMTMain {
    static func main() {
        // Recovery must remain independent of AppKit, SwiftUI and the parent's event loop.
        if let result = HyperRecoveryGuardian.runIfRequested(arguments: CommandLine.arguments) {
            exit(result)
        }
        guard HyperApplicationLease.acquire() else {
            fputs("XMT is already running, or its application lock is unavailable.\n", stderr)
            exit(1)
        }
        XMTApp.main()
    }
}

struct XMTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings is presented by the retained AppKit controller. This inert scene satisfies
        // SwiftUI's scene requirement without creating a second menu or window lifecycle.
        Settings { EmptyView() }
    }
}
