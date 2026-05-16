import SwiftUI

/// Popup contents while in `.notion` mode. One flat list, no category tabs.
struct NotionView: View {
    @ObservedObject var notion: NotionStore
    @ObservedObject var settings: AppSettings
    var onOpenSettings: () -> Void

    @State private var editingPage: NotionPage? = nil
    @State private var liveQuery: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            toolbar
        }
        .sheet(item: $editingPage) { p in
            NotionEditSheet(notion: notion, page: p) {
                editingPage = nil
            }
        }
        .onAppear { liveQuery = settings.notionQuery }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .foregroundColor(.black)
                .imageScale(.large)
            Text("Notion").font(.headline)
            Spacer()
            if let err = notion.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .truncationMode(.tail)
            } else if notion.isFetching {
                ProgressView().controlSize(.small)
                Text("Cargando…").font(.caption).foregroundColor(.secondary)
            } else if let when = notion.lastFetchedAt {
                Text("Actualizado \(timeAgo(from: when))")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("Sin datos").font(.caption).foregroundColor(.secondary)
            }
            Button {
                notion.fetch()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(notion.isFetching)
            .help("Refrescar ahora")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Buscar páginas…", text: $liveQuery)
                .textFieldStyle(.plain)
                .onSubmit { applySearch() }
            Picker("", selection: $settings.notionFilter) {
                Text("Páginas").tag("page")
                Text("Bases").tag("database")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()
            Button("Buscar") { applySearch() }
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func applySearch() {
        settings.notionQuery = liveQuery
        notion.fetch()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if notion.pages.isEmpty {
            VStack(spacing: 6) {
                Text("Sin páginas. Asegurate de tener `ntn` instalado y autenticado.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Abrir configuración") { onOpenSettings() }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(notion.pages) { p in
                        NotionPageRow(page: p) {
                            editingPage = p
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button { onOpenSettings() } label: { Label("Configuración", systemImage: "gearshape") }
            Spacer()
            Text("Total: \(notion.pages.count)")
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
