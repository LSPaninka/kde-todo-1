import SwiftUI

/// Configuración (Preferences). Tabs:
///   - General (modo, popup, etc.)
///   - Categorías locales (hasta 7)
///   - Apariencia (menubar / popup)
///   - Jira (conexión + JQL)
///   - Categorías Jira (filtros por pestaña)
///   - GitHub (token + owner + project)
///   - Categorías GitHub
///   - Notion (CLI + query)
struct SettingsView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var jira: JiraStore
    @ObservedObject var gh: GhStore
    @ObservedObject var notion: NotionStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            categoriesTab
                .tabItem { Label("Categorías", systemImage: "tag") }
            appearanceTab
                .tabItem { Label("Apariencia", systemImage: "paintbrush") }
            JiraSettingsView(jira: jira, settings: settings)
                .tabItem { Label("Jira", systemImage: "ant") }
            JiraCategoriesSettingsView(settings: settings)
                .tabItem { Label("Cat. Jira", systemImage: "rectangle.3.group") }
            GhSettingsView(gh: gh, settings: settings)
                .tabItem { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
            GhCategoriesSettingsView(settings: settings)
                .tabItem { Label("Cat. GH", systemImage: "square.grid.3x3") }
            NotionSettingsView(notion: notion, settings: settings)
                .tabItem { Label("Notion", systemImage: "doc.richtext") }
        }
        .frame(width: 620, height: 540)
        .padding()
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Modo") {
                Picker("Fuente de tareas", selection: $settings.mode) {
                    Text("Lista local (ToDo)").tag(AppMode.todo)
                    Text("Jira").tag(AppMode.jira)
                }
                .pickerStyle(.segmented)
                Text("ToDo = lista local guardada en este equipo. Jira = lee issues de tu cuenta vía API.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Categorías locales") {
                Stepper(value: Binding(
                    get: { settings.categoryCount },
                    set: { newValue in
                        let v = max(1, min(kMaxLocalCategories, newValue))
                        settings.categoryCount = v
                        store.reassignOutOfRange(newCount: v)
                    }),
                    in: 1...kMaxLocalCategories) {
                    Text("Cantidad activa: \(settings.categoryCount) (máx \(kMaxLocalCategories))")
                }
            }

            Section("Tareas") {
                Toggle("Mostrar insignias de prioridad",
                       isOn: $settings.showPriorityIcons)
                Toggle("Confirmar antes de borrar permanentemente",
                       isOn: $settings.confirmDelete)
            }

            Section("Tamaño del popup") {
                HStack {
                    Text("Ancho")
                    Slider(value: Binding(
                        get: { Double(settings.popupWidth) },
                        set: { settings.popupWidth = Int($0) }),
                        in: 320...720, step: 10)
                    Text("\(settings.popupWidth) px").monospacedDigit()
                }
                HStack {
                    Text("Alto")
                    Slider(value: Binding(
                        get: { Double(settings.popupHeight) },
                        set: { settings.popupHeight = Int($0) }),
                        in: 360...900, step: 10)
                    Text("\(settings.popupHeight) px").monospacedDigit()
                }
            }
        }
    }

    // MARK: - Categorías

    private var categoriesTab: some View {
        Form {
            ForEach(0..<kMaxLocalCategories, id: \.self) { i in
                Section("Categoría \(i + 1)\(i >= settings.categoryCount ? "  (oculta)" : "")") {
                    HStack {
                        TextField("Nombre", text: nameBinding(i))
                        ColorPicker("Color", selection: colorBinding(i), supportsOpacity: false)
                            .frame(width: 100)
                    }
                }
            }
        }
    }

    private func nameBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: {
                guard settings.categoryNames.indices.contains(i) else { return "" }
                return settings.categoryNames[i]
            },
            set: { newValue in
                while settings.categoryNames.count <= i {
                    settings.categoryNames.append("")
                }
                var arr = settings.categoryNames
                arr[i] = newValue
                settings.categoryNames = arr
            })
    }

    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(
            get: {
                guard settings.categoryColorsHex.indices.contains(i) else { return .gray }
                return Color(hex: settings.categoryColorsHex[i]) ?? .gray
            },
            set: { newColor in
                while settings.categoryColorsHex.count <= i {
                    settings.categoryColorsHex.append("#888888")
                }
                var arr = settings.categoryColorsHex
                arr[i] = newColor.toHex()
                settings.categoryColorsHex = arr
            })
    }

    // MARK: - Apariencia

    private var appearanceTab: some View {
        Form {
            Section("Barra de menús (macOS)") {
                Toggle("Usar un solo cuadrado con el total",
                       isOn: $settings.menuBarUseSingleSquare)
                ColorPicker("Color de fondo del cuadrado",
                            selection: Binding(
                                get: { Color(hex: settings.menuBarBackgroundHex) ?? .white },
                                set: { settings.menuBarBackgroundHex = $0.toHex() }),
                            supportsOpacity: false)
                Picker("Color del número",
                       selection: $settings.menuBarTextColor) {
                    Text("Negro").tag(CounterTextColor.black)
                    Text("Blanco").tag(CounterTextColor.white)
                }
                .pickerStyle(.segmented)
            }

            Section("Pestañas del popup") {
                Picker("Disposición del contador", selection: $settings.popupCounterLayout) {
                    Text("A la derecha").tag(CounterLayout.right)
                    Text("Dentro del cuadrado").tag(CounterLayout.inside)
                }
                .pickerStyle(.segmented)

                Toggle("Mostrar categorías con cero pendientes",
                       isOn: $settings.popupShowZero)

                ForEach(0..<settings.categoryCount, id: \.self) { i in
                    HStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(settings.categoryColor(i))
                            .frame(width: 16, height: 16)
                        Text(settings.categoryName(i))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker("", selection: textColorBinding(i)) {
                            Text("Blanco").tag(CounterTextColor.white)
                            Text("Negro").tag(CounterTextColor.black)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .labelsHidden()
                    }
                }
            }
        }
    }

    private func textColorBinding(_ i: Int) -> Binding<CounterTextColor> {
        Binding(
            get: {
                guard settings.popupCounterTextColors.indices.contains(i) else { return .white }
                return settings.popupCounterTextColors[i]
            },
            set: { newValue in
                while settings.popupCounterTextColors.count <= i {
                    settings.popupCounterTextColors.append(.white)
                }
                var arr = settings.popupCounterTextColors
                arr[i] = newValue
                settings.popupCounterTextColors = arr
            })
    }
}
