import AppKit
import Combine
import SwiftUI

/// Entry point.  SPM no soporta `@main struct ... : App`, así que armamos
/// el `NSApplication` a mano:  cargamos un `AppDelegate` que abre una
/// `NSWindow` con `NSHostingView(MainView)` adentro.
@main
struct WorklogCalendarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // La activation policy real (.regular vs .accessory) la define
        // `AppDelegate` según `settings.showInDock`.
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var settings: AppSettings!
    var jira: JiraWorklogStore!
    var jira2: JiraWorklogStore!
    var clockify: ClockifyStore!
    var google: GoogleCalendarStore!
    var statusBar: StatusBarController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = AppSettings()
        jira = JiraWorklogStore(settings: settings)
        jira2 = JiraWorklogStore(settings: settings, instanceId: 2)
        clockify = ClockifyStore(settings: settings)
        google = GoogleCalendarStore(settings: settings)

        // Los mismos stores alimentan tanto la ventana como el popover de
        // la barra de menús, así no se duplica el estado ni los fetch.
        let rootView = MainView(settings: settings, jira: jira, jira2: jira2, clockify: clockify, google: google)

        let initialSize = NSSize(width: CGFloat(settings.windowWidth),
                                 height: CGFloat(settings.windowHeight))
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // **Crítico**: por default `NSWindow` se libera al cerrar la
        // ventana (legacy retain count automático).  Como queremos que
        // cerrar con la X la oculte y deje la app viva en la barra de
        // menús para reabrirla después, le decimos a AppKit que NO
        // libere el objeto.  Sin esto, `applicationShouldHandleReopen`
        // dispara `makeKeyAndOrderFront(_:)` sobre memoria liberada y
        // crashea con `EXC_BAD_ACCESS` en `objc_msgSend`.
        window.isReleasedWhenClosed = false
        window.title = "Worklog Calendar"
        window.center()
        window.contentView = NSHostingView(rootView: rootView)
        window.minSize = NSSize(width: 720, height: 480)
        window.setFrameAutosaveName("WorklogCalendarMain")
        window.delegate = self

        // Política de activación inicial: con Dock (.regular) si el
        // usuario lo activó; si no, agent app (.accessory, sólo barra
        // de menús).
        applyActivationPolicy(settings.showInDock)

        // Ícono de reloj blanco en la barra de menús con el popover
        // compacto (Jira / Clockify).  El botón "abrir app" del popover
        // vuelve a traer esta ventana al frente.
        statusBar = StatusBarController(
            settings: settings,
            jira: jira,
            jira2: jira2,
            clockify: clockify,
            google: google,
            onOpenApp: { [weak self] in self?.showMainWindow() }
        )

        buildMainMenu()

        // En modo "con Dock" abrimos la ventana al arrancar (app normal).
        // En modo agent app arrancamos en silencio: sólo el ícono de la
        // barra de menús; la ventana se abre on-demand desde el popover.
        if settings.showInDock {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        // Aplicar el cambio en caliente cuando se togglea el setting.
        settings.$showInDock
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                self?.applyActivationPolicy(show)
            }
            .store(in: &cancellables)
    }

    /// Aplica `.regular` (ícono en Dock) o `.accessory` (sólo barra de
    /// menús).  Al volver a `.regular` traemos la ventana al frente.
    private func applyActivationPolicy(_ showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Trae la ventana principal al frente (la usa el botón "abrir app"
    /// del popover, y por si el usuario cerró la ventana y la reabre
    /// desde la barra de menús).
    func showMainWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        // No cerramos la app al cerrar la ventana: el popover de la barra
        // de menús sigue disponible.
        false
    }

    /// Reabrir desde el Dock cuando no hay ventanas visibles.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    private func buildMainMenu() {
        let menubar = NSMenu()
        // App menu (Worklog Calendar)
        let appMenuItem = NSMenuItem()
        menubar.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Acerca de Worklog Calendar",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferencias…",
                        action: #selector(openPreferences),
                        keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar Worklog Calendar",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu

        // Edit menu (estándar; sirve para Cmd-A, Cmd-C, etc. en los textfields).
        let editMenuItem = NSMenuItem()
        menubar.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edición")
        editMenu.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cortar",
                         action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copiar",
                         action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Pegar",
                         action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Seleccionar todo",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = menubar
    }

    @objc private func openPreferences() {
        // Disparamos el sheet con una NotificationCenter.  La MainView se
        // suscribe en su init.  Lo más sencillo: empujamos un click en
        // un botón virtual postNotification.
        NotificationCenter.default.post(name: .worklogOpenPreferences, object: nil)
    }
}

extension Notification.Name {
    static let worklogOpenPreferences = Notification.Name("WorklogOpenPreferences")
}

extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        settings.windowWidth = Int(win.frame.width)
        settings.windowHeight = Int(win.frame.height)
    }
}
