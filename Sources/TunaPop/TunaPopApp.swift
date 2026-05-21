import AppKit
import SwiftUI

@main
struct TunaPopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {}
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private var statusItem: NSStatusItem?
    private var monitor: SelectionMonitor?
    private var popupController: PopupController?
    private var selectionMonitoringItem: NSMenuItem?
    private var isSelectionMonitoringEnabled = false
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let popupController = PopupController(settings: settings)
        self.popupController = popupController

        monitor = SelectionMonitor { [weak self] payload, point in
            Task { @MainActor in
                guard let self, let controller = self.popupController else { return }
                if controller.isPointInOwnPanels(point) {
                    NSLog("tunaPop selection callback: ignored (point in own panel)")
                    return
                }
                controller.show(payload: payload, at: point)
            }
        }

        configureStatusItem()
        Accessibility.requestIfNeeded()
        NSLog("tunaPop permissions at launch: AX=\(Accessibility.isTrusted) InputMonitoring=\(InputMonitoring.isTrusted)")
        updateStatusItemAppearance()
        toggleSelectionMonitoring()

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItemAppearance()
            }
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "fish", accessibilityDescription: "tunaPop") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "tunaPop"
        }
        item.button?.toolTip = "tunaPop"

        let menu = NSMenu()
        let selectionMonitoringItem = NSMenuItem(
            title: "Enable Selection Monitor",
            action: #selector(toggleSelectionMonitoring),
            keyEquivalent: "m"
        )
        menu.addItem(selectionMonitoringItem)
        self.selectionMonitoringItem = selectionMonitoringItem
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check Accessibility", action: #selector(checkAccessibility), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        updateStatusItemAppearance()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "tunaPop Settings"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    @objc private func checkAccessibility() {
        Accessibility.requestIfNeeded()
        updateStatusItemAppearance()
    }


    @objc private func toggleSelectionMonitoring() {
        isSelectionMonitoringEnabled.toggle()

        if isSelectionMonitoringEnabled {
            monitor?.start()
            selectionMonitoringItem?.title = "Disable Selection Monitor"
            selectionMonitoringItem?.state = .on
        } else {
            monitor?.stop()
            selectionMonitoringItem?.title = "Enable Selection Monitor"
            selectionMonitoringItem?.state = .off
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let needsPermissions = !Accessibility.isTrusted
        button.contentTintColor = needsPermissions ? .systemOrange : nil
        button.toolTip = needsPermissions ? "tunaPop — 권한 필요" : "tunaPop"
    }
}
