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
    /// 780 alcanza para mostrar la franja 17:30–18:00 del calendario 9h
    /// que antes quedaba cortada en monitores con poca altura.
    static let popoverSize = NSSize(width: 1000, height: 780)

    /// Closure que el botón "Abrir aplicación" del menú contextual usa
    /// para traer la ventana grande al frente.
    private let onOpenApp: () -> Void

    init(settings: AppSettings,
         jira: JiraWorklogStore,
         clockify: ClockifyStore,
         onOpenApp: @escaping () -> Void) {
        self.onOpenApp = onOpenApp
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.clockImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Worklog Calendar — Jira / Clockify"
            button.action = #selector(togglePopover(_:))
            button.target = self
            // También aceptamos el right-up para mostrar el menú
            // contextual con "Abrir aplicación" + "Salir".
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
                self?.onOpenApp()
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
        // Right-click (o ctrl-click) → menú contextual con Abrir / Salir.
        // Sólo así se puede cerrar la app — cerrar la ventana grande la
        // deja viva en la barra de menús.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
            return
        }
        // Left-click → toggle del popover.
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Abrir aplicación",
                              action: #selector(openAppFromMenu(_:)),
                              keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir",
                              action: #selector(quitApp(_:)),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func openAppFromMenu(_ sender: Any?) {
        closePopover()
        onOpenApp()
    }
    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
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

    /// SF Symbol "clock" como **template image** — macOS lo tinta solo
    /// según el contexto de la barra de menús (blanco en barra oscura,
    /// negro en barra clara, perfectamente nítido a cualquier DPI).
    /// La versión previa usaba `paletteColors: [.white]` + `isTemplate
    /// = false`, lo que en monitores 1080×720 derivaba en un glifo
    /// distorsionado ("(_)") porque el rasterizador elegía variantes
    /// de tamaño incorrectas.
    private static func clockImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: "clock",
                            accessibilityDescription: "Worklog Calendar")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
