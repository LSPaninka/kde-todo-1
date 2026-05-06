import SwiftUI

/// Popup contents while in `.jira` mode. Tabs across the top (one per
/// configured Jira category), refresh button, list of issues.
struct JiraView: View {
    @ObservedObject var jira: JiraStore
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
        .onChange(of: settings.jiraCategoryCount) { _ in clampSelection() }
    }

    private func clampSelection() {
        if selection >= settings.jiraCategoryCount {
            selection = max(0, settings.jiraCategoryCount - 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "ant.circle.fill")
                .foregroundColor(.blue)
                .imageScale(.large)
            Text("Jira").font(.headline)

            Spacer()

            if let err = jira.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if jira.isFetching {
                ProgressView()
                    .controlSize(.small)
                Text("Cargando…").font(.caption).foregroundColor(.secondary)
            } else if let when = jira.lastFetchedAt {
                Text("Actualizado \(timeAgo(from: when))")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("Sin datos").font(.caption).foregroundColor(.secondary)
            }

            Button {
                jira.fetch()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(jira.isFetching)
            .help("Refrescar ahora")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<settings.jiraCategoryCount, id: \.self) { i in
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
        let color = settings.jiraCategoryColor(index)
        let n = jira.count(forCategory: index)

        Button {
            selection = index
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: 12)
                Text(settings.jiraCategoryName(index))
                    .lineLimit(1)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(minWidth: 18, minHeight: 16)
                    Text("\(n)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(settings.jiraCategoryTextColor(index))
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
        let items = jira.issues(forCategory: selection)
        if items.isEmpty {
            VStack(spacing: 6) {
                if jira.issues.isEmpty {
                    Text("Sin issues. Configurá la conexión a Jira y refrescá.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Abrir configuración") { onOpenSettings() }
                        .controlSize(.small)
                } else {
                    Text("Ningún issue cae en esta pestaña con el filtro actual.")
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
                        JiraIssueRow(issue: it)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                Label("Configuración", systemImage: "gearshape")
            }
            Spacer()
            Text("Total: \(jira.issues.count)")
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Salir", systemImage: "power")
            }
        }
        .padding(8)
    }

    // MARK: - Helpers

    private func timeAgo(from date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
