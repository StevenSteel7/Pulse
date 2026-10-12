import SwiftUI
import AppKit

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: PulseMonitor

    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-widget-cache") {
            SharedStore.resetSnapshotCache()
        }
        _monitor = StateObject(wrappedValue: PulseMonitor())
    }

    var body: some Scene {
        // No default window scene: launching or clicking a desktop widget
        // keeps Pulse in the menu bar. Only Advanced creates the dashboard.
        MenuBarExtra {
            MenuBarContentView {
                appDelegate.showAdvanced(monitor: monitor)
            }
            .environmentObject(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var advancedWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func showAdvanced(monitor: PulseMonitor) {
        if advancedWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 680),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Pulse · Advanced"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.055, green: 0.07, blue: 0.12, alpha: 1)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentView = NSHostingView(rootView: DashboardView().environmentObject(monitor))
            window.center()
            advancedWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        advancedWindow?.makeKeyAndOrderFront(nil)
    }
}
