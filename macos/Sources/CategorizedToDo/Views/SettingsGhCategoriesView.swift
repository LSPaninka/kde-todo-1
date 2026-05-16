import SwiftUI

/// Settings tab — per-tab filter configuration for GitHub Projects mode.
struct GhCategoriesSettingsView: View {
    @ObservedObject var settings: AppSettings

    private let fieldOptions: [(label: String, value: String, hint: String)] = [
        ("(sin filtro)", "", "muestra todos los items"),
        ("status",       "status", "Todo ; In progress ; Done"),
        ("type",         "type",   "Issue ; PullRequest ; DraftIssue"),
        ("state",        "state",  "OPEN ; CLOSED ; MERGED ; DRAFT"),
        ("repo",         "repo",   "owner/repo ; owner/other-repo"),
        ("label",        "label",  "bug ; chore ; help wanted")
    ]

    var body: some View {
        Form {
            Section("Pestañas activas") {
                Stepper(value: $settings.ghCategoryCount, in: 1...4) {
                    Text("Cantidad: \(settings.ghCategoryCount)")
                }
            }

            ForEach(0..<4, id: \.self) { i in
                Section("Pestaña \(i + 1)\(i >= settings.ghCategoryCount ? "  (oculta)" : "")") {
                    HStack {
                        TextField("Nombre", text: nameBinding(i))
                        ColorPicker("Color", selection: colorBinding(i), supportsOpacity: false)
                            .frame(width: 100)
                    }
                    Picker("Color del número", selection: textColorBinding(i)) {
                        Text("Blanco").tag(CounterTextColor.white)
                        Text("Negro").tag(CounterTextColor.black)
                    }
                    .pickerStyle(.segmented)

                    Picker("Filtrar por", selection: fieldBinding(i)) {
                        ForEach(fieldOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }

                    let field = settings.ghCategoryFilterFields.indices.contains(i)
                        ? settings.ghCategoryFilterFields[i]
                        : ""
                    if !field.isEmpty {
                        TextField("Valores (separados por ;)", text: valueBinding(i))
                            .font(.system(.body, design: .monospaced))
                        Text("Ejemplo: \(hint(for: field))")
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        Text("Sin filtro: muestra todos los items.")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func hint(for field: String) -> String {
        fieldOptions.first(where: { $0.value == field })?.hint ?? ""
    }

    // MARK: - Bindings

    private func nameBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { settings.ghCategoryNames.indices.contains(i) ? settings.ghCategoryNames[i] : "" },
            set: { newValue in
                while settings.ghCategoryNames.count <= i { settings.ghCategoryNames.append("") }
                var arr = settings.ghCategoryNames; arr[i] = newValue
                settings.ghCategoryNames = arr
            })
    }

    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(
            get: {
                guard settings.ghCategoryColorsHex.indices.contains(i) else { return .gray }
                return Color(hex: settings.ghCategoryColorsHex[i]) ?? .gray
            },
            set: { newColor in
                while settings.ghCategoryColorsHex.count <= i { settings.ghCategoryColorsHex.append("#888888") }
                var arr = settings.ghCategoryColorsHex; arr[i] = newColor.toHex()
                settings.ghCategoryColorsHex = arr
            })
    }

    private func textColorBinding(_ i: Int) -> Binding<CounterTextColor> {
        Binding(
            get: { settings.ghCategoryTextColors.indices.contains(i) ? settings.ghCategoryTextColors[i] : .white },
            set: { newValue in
                while settings.ghCategoryTextColors.count <= i { settings.ghCategoryTextColors.append(.white) }
                var arr = settings.ghCategoryTextColors; arr[i] = newValue
                settings.ghCategoryTextColors = arr
            })
    }

    private func fieldBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { settings.ghCategoryFilterFields.indices.contains(i) ? settings.ghCategoryFilterFields[i] : "" },
            set: { newValue in
                while settings.ghCategoryFilterFields.count <= i { settings.ghCategoryFilterFields.append("") }
                var arr = settings.ghCategoryFilterFields; arr[i] = newValue
                settings.ghCategoryFilterFields = arr
            })
    }

    private func valueBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { settings.ghCategoryFilterValues.indices.contains(i) ? settings.ghCategoryFilterValues[i] : "" },
            set: { newValue in
                while settings.ghCategoryFilterValues.count <= i { settings.ghCategoryFilterValues.append("") }
                var arr = settings.ghCategoryFilterValues; arr[i] = newValue
                settings.ghCategoryFilterValues = arr
            })
    }
}
