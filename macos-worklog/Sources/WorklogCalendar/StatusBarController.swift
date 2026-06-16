import AppKit
import SwiftUI

/// Monitor de eventos global: dispara `handler` cuando el usuario hace
/// click FUERA de la app (en otra app o el escritorio).  Lo usamos para
/// cerrar el popover al perder el foco sin recurrir al comportamiento
/// `.transient` de NSPopover, que cerraría el popover apenas se abre un
/// sheet de edición (worklog nuevo, etc.).
final class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

/// Ícono de reloj blanco en la barra de menús superior + popover de
/// 1000×700 con la vista de worklog (planilla + anillos + heatmap +
/// sync) reusando `MainView`.
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var eventMonitor: EventMonitor?

    /// Tamaño compacto del popover (todo a escala dentro de este lienzo).
    static let popoverSize = NSSize(width: 1000, height: 700)

    init(settings: AppSettings,
         jira: JiraWorklogStore,
         clockify: ClockifyStore,
         onOpenApp: @escaping () -> Void) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.clockImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Worklog Calendar — Jira / Clockify"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // `.applicationDefined`: el popover sólo se cierra cuando se lo
        // pedimos explícitamente (toggle del ícono, botón "abrir app" o
        // el EventMonitor de clicks fuera de la app).  Así un sheet de
        // edición abierto desde adentro no lo tira abajo.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = Self.popoverSize

        let root = MainView(
            settings: settings,
            jira: jira,
            clockify: clockify,
            onOpenApp: { [weak self] in
                self?.closePopover()
                onOpenApp()
            }
        )
        .frame(width: Self.popoverSize.width, height: Self.popoverSize.height)

        popover.contentViewController = NSHostingController(rootView: root)

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    // MARK: - Toggle

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        eventMonitor?.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover.performClose(nil)
        eventMonitor?.stop()
    }

    // MARK: - Ícono

    /// Reloj blanco (SF Symbol "clock").  `isTemplate = false` + palette
    /// blanca para que la barra de menús no lo recoloreé.
    private static func clockImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let image = NSImage(systemSymbolName: "clock",
                            accessibilityDescription: "Worklog Calendar")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        return image ?? NSImage()
    }
}
