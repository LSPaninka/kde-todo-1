import SwiftUI

/// Settings tab — Jira categories (per-tab name, color, filter dimension and
/// values). Up to 4 slots; the active count is editable here too.
struct JiraCategoriesSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Pestañas activas") {
                Stepper(value: $settings.jiraCategoryCount, in: 1...4) {
                    Text("Cantidad: \(settings.jiraCategoryCount)")
                }
                Text("Cada pestaña filtra los issues que vienen de la JQL configurada en la pestaña 'Jira'.")
                    .font(.caption).foregroundColor(.secondary)
            }

            ForEach(0..<4, id: \.self) { i in
                Section("Pestaña \(i + 1)\(i >= settings.jiraCategoryCount ? "  (oculta)" : "")") {
                    HStack {
                        TextField("Nombre", text: nameBinding(i))
                        ColorPicker("Color",
                                    selection: colorBinding(i),
                                    supportsOpacity: false)
                            .frame(width: 100)
                    }

                    Picker("Color del número", selection: textColorBinding(i)) {
                        Text("Blanco").tag(CounterTextColor.white)
                        Text("Negro").tag(CounterTextColor.black)
                    }
                    .pickerStyle(.segmented)

                    Picker("Filtrar por", selection: fieldBinding(i)) {
                        ForEach(JiraFilterField.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }

                    let field = settings.jiraCategoryFilterFields.indices.contains(i)
                        ? settings.jiraCategoryFilterFields[i]
                        : .none
                    if field != .none {
                        TextField("Valores (separados por ;)",
                                  text: valueBinding(i))
                            .font(.system(.body, design: .monospaced))
                        Text("Ejemplo: \(field.placeholderHint)")
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        Text("Sin filtro: muestra todos los issues retornados por la JQL.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Bindings

    private func nameBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: {
                guard settings.jiraCategoryNames.indices.contains(i) else { return "" }
                return settings.jiraCategoryNames[i]
            },
            set: { newValue in
                while settings.jiraCategoryNames.count <= i {
                    settings.jiraCategoryNames.append("")
                }
                var arr = settings.jiraCategoryNames
                arr[i] = newValue
                settings.jiraCategoryNames = arr
            })
    }

    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(
            get: {
                guard settings.jiraCategoryColorsHex.indices.contains(i) else { return .gray }
                return Color(hex: settings.jiraCategoryColorsHex[i]) ?? .gray
            },
            set: { newColor in
                while settings.jiraCategoryColorsHex.count <= i {
                    settings.jiraCategoryColorsHex.append("#888888")
                }
                var arr = settings.jiraCategoryColorsHex
                arr[i] = newColor.toHex()
                settings.jiraCategoryColorsHex = arr
            })
    }

    private func textColorBinding(_ i: Int) -> Binding<CounterTextColor> {
        Binding(
            get: {
                guard settings.jiraCategoryTextColors.indices.contains(i) else { return .white }
                return settings.jiraCategoryTextColors[i]
            },
            set: { newValue in
                while settings.jiraCategoryTextColors.count <= i {
                    settings.jiraCategoryTextColors.append(.white)
                }
                var arr = settings.jiraCategoryTextColors
                arr[i] = newValue
                settings.jiraCategoryTextColors = arr
            })
    }

    private func fieldBinding(_ i: Int) -> Binding<JiraFilterField> {
        Binding(
            get: {
                guard settings.jiraCategoryFilterFields.indices.contains(i) else { return .none }
                return settings.jiraCategoryFilterFields[i]
            },
            set: { newValue in
                while settings.jiraCategoryFilterFields.count <= i {
                    settings.jiraCategoryFilterFields.append(.none)
                }
                var arr = settings.jiraCategoryFilterFields
                arr[i] = newValue
                settings.jiraCategoryFilterFields = arr
            })
    }

    private func valueBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: {
                guard settings.jiraCategoryFilterValues.indices.contains(i) else { return "" }
                return settings.jiraCategoryFilterValues[i]
            },
            set: { newValue in
                while settings.jiraCategoryFilterValues.count <= i {
                    settings.jiraCategoryFilterValues.append("")
                }
                var arr = settings.jiraCategoryFilterValues
                arr[i] = newValue
                settings.jiraCategoryFilterValues = arr
            })
    }
}
