import AppKit
import SwiftUI
import Combine

/// Owns the menu-bar status item and the popover that contains the popup.
/// Re-renders the menu-bar icon whenever any of the stores or the settings
/// change. Right-clicking the status item opens a context menu with the
/// "switch mode" cycle (todo → jira → gh → notion).
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()

    private let store: TaskStore
    private let jira: JiraStore
    private let gh: GhStore
    private let notion: NotionStore
    private let settings: AppSettings
    private weak var settingsWindowController: NSWindowController?

    init(store: TaskStore,
         jira: JiraStore,
         gh: GhStore,
         notion: NotionStore,
         settings: AppSettings) {
        self.store = store
        self.jira = jira
        self.gh = gh
        self.notion = notion
        self.settings = settings

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: settings.popupWidth,
                                     height: settings.popupHeight)

        super.init()

        let popup = PopupView(store: store,
                              settings: settings,
                              jira: jira,
                              gh: gh,
                              notion: notion,
                              onOpenSettings: { [weak self] in self?.openSettings() })
        popover.contentViewController = NSHostingController(rootView: popup)

        configureButton()

        let publishers: [AnyPublisher<Void, Never>] = [
            store.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            jira.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            gh.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            notion.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            settings.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(publishers)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshIcon()
                self.popover.contentSize = NSSize(width: self.settings.popupWidth,
                                                  height: self.settings.popupHeight)
            }
            .store(in: &cancellables)

        refreshIcon()
    }

    // MARK: - Status item

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        // Listen for both left and right mouse buttons so right-click can
        // open the context menu instead of the popover.
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.image?.isTemplate = false
    }

    @objc private func handleClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { togglePopover(sender); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: AnyObject?) {
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

    private func showContextMenu() {
        let menu = NSMenu()

        // Mode submenu — one row per mode, current one with a checkmark.
        let modeHeader = NSMenuItem(title: "Modo",
                                    action: nil,
                                    keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)
        for (i, m) in AppMode.allCases.enumerated() {
            let item = NSMenuItem(title: "  \(m.displayName)",
                                  action: #selector(switchMode(_:)),
                                  keyEquivalent: String(i + 1))
            item.target = self
            item.representedObject = m.rawValue
            item.state = (m == settings.mode) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())

        // Refresh of the current mode.
        let refreshTitle: String
        switch settings.mode {
        case .todo:   refreshTitle = "Recargar tareas"
        case .jira:   refreshTitle = "Refrescar Jira ahora"
        case .gh:     refreshTitle = "Refrescar GitHub ahora"
        case .notion: refreshTitle = "Refrescar Notion ahora"
        }
        let refresh = NSMenuItem(title: refreshTitle,
                                 action: #selector(refreshCurrent),
                                 keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let prefs = NSMenuItem(title: "Configuración…",
                               action: #selector(openSettingsAction),
                               keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Salir",
                              action: #selector(quitApp),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Show under the status item button.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil    // restore so normal click toggles the popover
    }

    @objc private func switchMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AppMode(rawValue: raw) else { return }
        settings.mode = mode
    }

    @objc private func refreshCurrent() {
        switch settings.mode {
        case .todo:
            store.load()
        case .jira:
            jira.fetch()
        case .gh:
            gh.fetch()
        case .notion:
            notion.fetch()
        }
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon rendering

    func refreshIcon() {
        let view = MenuBarIcon(store: store,
                               jira: jira,
                               gh: gh,
                               notion: notion,
                               settings: settings)
            .frame(height: 18)
            .padding(.horizontal, 1)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let nsImage = renderer.nsImage {
            nsImage.isTemplate = false
            statusItem.button?.image = nsImage
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            let n: Int
            switch settings.mode {
            case .todo:   n = store.totalPending
            case .jira:   n = jira.issues.count
            case .gh:     n = gh.items.count
            case .notion: n = notion.pages.count
            }
            statusItem.button?.title = "\(n)"
        }
    }

    // MARK: - Settings window

    func openSettings() {
        if let wc = settingsWindowController {
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(store: store,
                                jira: jira,
                                gh: gh,
                                notion: notion,
                                settings: settings)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Categorized ToDo — Configuración"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 560))
        window.center()
        let wc = NSWindowController(window: window)
        settingsWindowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if popover.isShown { popover.performClose(nil) }
    }
}
