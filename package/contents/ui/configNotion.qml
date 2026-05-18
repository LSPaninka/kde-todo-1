/*
 * configNotion.qml - Notion tab of the configuration dialog.
 *
 * Notion auth is delegated to the `ntn` CLI — the user runs `ntn login`
 * once (or exports NOTION_API_TOKEN) and the plasmoid just shells out.
 * Hence no token field here. Only what the search call needs.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property alias  cfg_notionQuery:           queryField.text
    property string cfg_notionFilter:          "page"
    property alias  cfg_notionMaxResults:      maxSpin.value
    property alias  cfg_notionRefreshMinutes:  refreshSpin.value
    property alias  cfg_notionCliPath:         pathField.text
    property alias  cfg_notionDebug:           debugCheck.checked

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("El modo Notion usa el CLI oficial `ntn` para listar y editar páginas. "
                 + "Antes de usarlo, corré una vez `ntn login` en una terminal (o exportá "
                 + "NOTION_API_TOKEN en tu sesión). El plasmoide no guarda tokens.")
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        TextField {
            id: queryField
            Kirigami.FormData.label: i18n("Búsqueda (opcional):")
            Layout.fillWidth: true
            placeholderText: i18n("Texto a buscar — vacío trae todas las páginas")
        }

        ButtonGroup { id: filterGroup }
        RowLayout {
            Kirigami.FormData.label: i18n("Filtrar por:")
            RadioButton {
                ButtonGroup.group: filterGroup
                text: i18n("Páginas")
                checked: page.cfg_notionFilter !== "database"
                onToggled: if (checked) page.cfg_notionFilter = "page"
            }
            RadioButton {
                ButtonGroup.group: filterGroup
                text: i18n("Bases de datos")
                checked: page.cfg_notionFilter === "database"
                onToggled: if (checked) page.cfg_notionFilter = "database"
            }
        }

        SpinBox {
            id: maxSpin
            Kirigami.FormData.label: i18n("Máx. resultados:")
            from: 10
            to: 200
            stepSize: 10
        }

        SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Auto-refresh (min):")
            from: 0
            to: 1440
            stepSize: 1
        }

        TextField {
            id: pathField
            Kirigami.FormData.label: i18n("Ruta de `ntn`:")
            Layout.fillWidth: true
            placeholderText: i18n("Dejar vacío = usar PATH. Ej: /home/user/.local/bin/ntn")
        }

        CheckBox {
            id: debugCheck
            Kirigami.FormData.label: i18n("Logs:")
            text: i18n("Loggear cada comando ntn y su salida en plasmashell")
        }
    }

    GroupBox {
        Layout.fillWidth: true
        title: i18n("Cómo configurar ntn")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("1) Instalá el CLI:")
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.family: "monospace"
                text: "    curl -fsSL https://ntn.dev | bash"
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("2) Autenticate (abre tu navegador):")
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.family: "monospace"
                text: "    ntn login"
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("3) (Opcional) probá listar páginas a mano para validar:")
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.family: "monospace"
                text: "    ntn api v1/search -X POST -d '{\"page_size\":5}'"
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("Más detalles en docs/NOTION.md.")
            }
        }
    }

    Item { Layout.fillHeight: true }
}
