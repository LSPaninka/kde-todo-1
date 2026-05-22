import SwiftUI

/// Donut con un porcentaje en el centro.  Replica `RingGauge.qml`:
///   - Anima el fill de 0 → `value` al llamar `startFill()` (al abrir
///     el popup o al cambiar la fuente).
///   - Opcionalmente cicla `baseColor` ↔ `paleColor` para llamar la
///     atención (lo usa el anillo "Horas" cuando estás atrasado).
///   - Track gris de fondo + arco anti-aliased con linecap redondo.
struct RingGauge: View {
    var value: Double                      // target 0..100
    var baseColor: Color = Color(red: 129/255, green: 199/255, blue: 132/255)  // #81C784
    var paleColor: Color = Color(red: 200/255, green: 230/255, blue: 201/255)  // #C8E6C9
    var trackColor: Color = Color(white: 0.16)
    var thickness: CGFloat = 12
    var diameter: CGFloat = 110

    /// Si `true`, anima el color del aro entre `baseColor` y `paleColor`
    /// en loop para llamar la atención.
    var useFadeLoop: Bool = false
    /// Si `true`, el loop es más rápido (1 s + 1 s; sin él 3 s + 1.5 s).
    var intermittent: Bool = false

    /// `Binding` opcional: cuando se cambia desde afuera, el ring
    /// anima de 0 → target.  Lo usa `MainView` para re-disparar la
    /// animación cuando se reabre el panel.
    @State private var displayValue: Double = 0
    @State private var fadeOn: Bool = false

    var body: some View {
        ZStack {
            // Track (círculo completo).
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: thickness, lineCap: .round))

            // Arco coloreado, animado.
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, displayValue)) / 100))
                .stroke(currentColor, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(displayValue.rounded()))%")
                .font(.system(size: diameter * 0.22, weight: .bold))
        }
        .frame(width: diameter, height: diameter)
        // Cuando el valor objetivo cambia (refetch del sprint), animamos
        // suavemente hacia el nuevo target.
        .onAppear { startFill() }
        .onChange(of: value) { _ in
            withAnimation(.easeOut(duration: 1.0)) {
                displayValue = value
            }
        }
        // Loop de fade: alterna `fadeOn` y dejamos que `animation` haga
        // la interpolación de color.  Sin `useFadeLoop`, el color queda
        // fijo en `baseColor`.
        .onChange(of: useFadeLoop) { on in restartFade(on: on) }
        .onChange(of: intermittent)  { _ in restartFade(on: useFadeLoop) }
        .onAppear { restartFade(on: useFadeLoop) }
    }

    /// Inicia la animación de fill 0% → `value`.  Útil al reabrir el popup.
    func startFill() {
        displayValue = 0
        withAnimation(.easeOut(duration: 1.5)) {
            displayValue = value
        }
    }

    private var currentColor: Color {
        guard useFadeLoop else { return baseColor }
        return fadeOn ? paleColor : baseColor
    }

    private func restartFade(on: Bool) {
        fadeOn = false
        guard on else { return }
        let halfCycle = intermittent ? 1.0 : 1.5
        let pause     = intermittent ? 1.0 : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
            withAnimation(.easeInOut(duration: halfCycle).repeatForever(autoreverses: true)) {
                fadeOn = true
            }
        }
    }
}
