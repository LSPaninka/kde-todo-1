import AppKit
import SwiftUI
import Combine

/// Owns the menu-bar status item and the popover that contains the popup.
/// Re-renders the menu-bar icon whenever the store or settings change.
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()

    private let store: TaskStore
    private let settings: AppSettings
    private weak var settingsWindowController: NSWindowController?

    init(store: TaskStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: settings.popupWidth,
                                     height: settings.popupHeight)

        let popup = PopupView(store: store, settings: settings,
                              onOpenSettings: { [weak self] in
            self?.openSettings()
        })
        popover.contentViewController = NSHostingController(rootView: popup)

        configureButton()

        // Refresh the menu-bar icon on any change.
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIcon()
                self?.popover.contentSize = NSSize(width: settings.popupWidth,
                                                   height: settings.popupHeight)
            }
            .store(in: &cancellables)

        refreshIcon()
    }

    // MARK: - Status item

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageOnly
        // Important: don't tint the image — we want the white square as-is.
        button.image?.isTemplate = false
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds,
                         of: button,
                         preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Icon rendering

    /// Render the SwiftUI MenuBarIcon to an NSImage and assign it to the
    /// status-item button.
    func refreshIcon() {
        let view = MenuBarIcon(store: store, settings: settings)
            .frame(height: 18)
            .padding(.horizontal, 1)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let nsImage = renderer.nsImage {
            nsImage.isTemplate = false
            statusItem.button?.image = nsImage
            statusItem.button?.title = ""
        } else {
            // Fallback if renderer fails: just text.
            statusItem.button?.image = nil
            statusItem.button?.title = "\(store.totalPending)"
        }
    }

    // MARK: - Settings window

    func openSettings() {
        if let wc = settingsWindowController {
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(store: store, settings: settings)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Categorized ToDo — Configuración"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 540, height: 480))
        window.center()
        let wc = NSWindowController(window: window)
        settingsWindowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Close popover so the user can interact with the window.
        if popover.isShown { popover.performClose(nil) }
    }
}
