import SwiftUI

/// Popup contents while in `.gh` (GitHub Projects) mode.
struct GhView: View {
    @ObservedObject var gh: GhStore
    @ObservedObject var settings: AppSettings
    var onOpenSettings: () -> Void

    @State private var selection: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            toolbar
        }
        .onAppear { clampSelection() }
        .onChange(of: settings.ghCategoryCount) { _ in clampSelection() }
    }

    private func clampSelection() {
        if selection >= settings.ghCategoryCount {
            selection = max(0, settings.ghCategoryCount - 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .foregroundColor(.purple)
                .imageScale(.large)
            Text("GitHub Projects").font(.headline)
            Spacer()
            if let err = gh.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .truncationMode(.tail)
            } else if gh.isFetching {
                ProgressView().controlSize(.small)
                Text("Cargando…").font(.caption).foregroundColor(.secondary)
            } else if let when = gh.lastFetchedAt {
                Text("Actualizado \(timeAgo(from: when))")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("Sin datos").font(.caption).foregroundColor(.secondary)
            }
            Button {
                gh.fetch()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(gh.isFetching)
            .help("Refrescar ahora")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<settings.ghCategoryCount, id: \.self) { i in
                tab(index: i)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func tab(index: Int) -> some View {
        let selected = (selection == index)
        let color = settings.ghCategoryColor(index)
        let n = gh.count(forCategory: index)

        Button { selection = index } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 12)
                Text(settings.ghCategoryName(index))
                    .lineLimit(1)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(minWidth: 18, minHeight: 16)
                    Text("\(n)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(settings.ghCategoryTextColor(index))
                        .padding(.horizontal, 4)
                        .monospacedDigit()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.5) : Color.clear,
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let items = gh.items(forCategory: selection)
        if items.isEmpty {
            VStack(spacing: 6) {
                if gh.items.isEmpty {
                    Text("Sin items. Configurá la conexión y refrescá.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Abrir configuración") { onOpenSettings() }
                        .controlSize(.small)
                } else {
                    Text("Ningún item cae en esta pestaña con el filtro actual.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { it in
                        GhItemRow(item: it, settings: settings)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button { onOpenSettings() } label: { Label("Configuración", systemImage: "gearshape") }
            Spacer()
            Text("Total: \(gh.items.count)")
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Button { NSApp.terminate(nil) } label: { Label("Salir", systemImage: "power") }
        }
        .padding(8)
    }

    private func timeAgo(from date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
