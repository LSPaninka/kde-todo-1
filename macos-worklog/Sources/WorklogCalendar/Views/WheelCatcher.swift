import AppKit
import SwiftUI

/// Observador no-consumidor de scroll-wheel.  Se monta vía
/// `.background(WheelCatcher { dy in … })` sobre cualquier view SwiftUI
/// y dispara el callback con el `scrollingDeltaY` cuando el cursor
/// está sobre la view envuelta — sin tocar los clicks ni mover el
/// scrolling original (devuelve el evento).
struct WheelCatcher: NSViewRepresentable {
    /// `deltaY > 0` = rueda / trackpad hacia arriba.
    let onWheel: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.hostView = v
        context.coordinator.onWheel = onWheel
        DispatchQueue.main.async { context.coordinator.install() }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWheel = onWheel
    }

    final class Coordinator {
        weak var hostView: NSView?
        var onWheel: (CGFloat) -> Void = { _ in }
        private var monitor: Any?

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.maybeFire(event: event)
                return event   // no consumimos: el scroll original sigue
            }
        }

        private func maybeFire(event: NSEvent) {
            guard let v = hostView,
                  let win = v.window,
                  event.window === win else { return }
            // Convertimos location-en-ventana al espacio de la NSView.
            let loc = v.convert(event.locationInWindow, from: nil)
            if v.bounds.contains(loc) {
                onWheel(event.scrollingDeltaY)
            }
        }
    }
}
