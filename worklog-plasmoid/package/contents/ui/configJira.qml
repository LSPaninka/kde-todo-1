/*
 * configJira.qml - Jira credentials tab.
 *
 * Shares jiraSite / jiraEmail / jiraToken with the Categorized ToDo plasmoid
 * via the same kcfg file (categorizedtodorc). Editing here updates both.
 *
 * Includes a "Test connection" button that GETs /rest/api/3/myself with the
 * values currently in the form (not necessarily saved yet).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property alias cfg_jiraSite:  siteField.text
    property alias cfg_jiraEmail: emailField.text
    property alias cfg_jiraToken: tokenField.text

    // Second Jira instance (worklog plasmoid only).
    property alias cfg_jira2Enabled: jira2EnabledCheck.checked
    property alias cfg_jira2Site:    site2Field.text
    property alias cfg_jira2Email:   email2Field.text
    property alias cfg_jira2Token:   token2Field.text

    // Per-instance block colors (hex, drawn translucent on the calendar).
    property string cfg_jira1BlockColor: "#9b91e6"
    property string cfg_jira2BlockColor: "#26a69a"

    // Color picker state.
    property int _colorTarget: 1   // 1 = Jira 1, 2 = Jira 2
    readonly property var _palette: ["#9b91e6", "#7e57c2", "#5c6bc0", "#42a5f5",
                                     "#26a69a", "#66bb6a", "#ef5350", "#ec407a",
                                     "#ffa726", "#8d6e63", "#78909c"]

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Estas credenciales están compartidas con el plasmoide «Categorized ToDo». "
                 + "Si ya las configuraste allá, no hace falta volver a escribirlas. El token "
                 + "se guarda en plain text en ~/.config/categorizedtodorc (permisos 0600).")
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        TextField {
            id: siteField
            Kirigami.FormData.label: i18n("Sitio Jira:")
            Layout.fillWidth: true
            placeholderText: "https://your-company.atlassian.net"
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
        }

        TextField {
            id: emailField
            Kirigami.FormData.label: i18n("Email:")
            Layout.fillWidth: true
            placeholderText: "you@example.com"
            inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoPredictiveText
        }

        RowLayout {
            Kirigami.FormData.label: i18n("API token:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: tokenField
                Layout.fillWidth: true
                echoMode: showTokenCheck.checked ? TextInput.Normal : TextInput.Password
                placeholderText: i18n("Generado en id.atlassian.com")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            }
            CheckBox {
                id: showTokenCheck
                text: i18n("Ver")
            }
        }
    }

    GroupBox {
        Layout.fillWidth: true
        title: i18n("Probar conexión")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: i18n("Probar")
                    icon.name: "network-connect"
                    onClicked: {
                        statusLabel.text = i18n("Conectando…");
                        statusLabel.color = palette.text;
                        page._test(siteField.text, emailField.text, tokenField.text, statusLabel);
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Label {
                id: statusLabel
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: ""
            }
        }
    }

    // -------- Block colors --------
    GroupBox {
        Layout.fillWidth: true
        title: i18n("Colores de bloque")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.75
                text: i18n("Color de los bloques de cada Jira en los modos Jira y Jira/Clockify "
                         + "(se dibujan translúcidos). Sirve para distinguir las dos instancias.")
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Label { text: i18n("Jira 1:") }
                Rectangle {
                    Layout.preferredWidth: 40; Layout.preferredHeight: 22
                    radius: 3; color: page.cfg_jira1BlockColor
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.4)
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { page._colorTarget = 1; colorPopup.open(); }
                    }
                }
                Item { Layout.preferredWidth: Kirigami.Units.largeSpacing }
                Label { text: i18n("Jira 2:") }
                Rectangle {
                    Layout.preferredWidth: 40; Layout.preferredHeight: 22
                    radius: 3; color: page.cfg_jira2BlockColor
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.4)
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { page._colorTarget = 2; colorPopup.open(); }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // -------- Second Jira instance --------
    GroupBox {
        Layout.fillWidth: true
        title: i18n("Segundo Jira")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            CheckBox {
                id: jira2EnabledCheck
                text: i18n("Habilitar una segunda instancia de Jira")
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("Credenciales independientes (NO se comparten con el plasmoide ToDo). "
                         + "El panel inferior (anillos / subtareas / heatmap) sigue atado al primer Jira.")
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true
                enabled: jira2EnabledCheck.checked

                TextField {
                    id: site2Field
                    Kirigami.FormData.label: i18n("Sitio Jira:")
                    Layout.fillWidth: true
                    placeholderText: "https://other.atlassian.net"
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                }
                TextField {
                    id: email2Field
                    Kirigami.FormData.label: i18n("Email:")
                    Layout.fillWidth: true
                    placeholderText: "you@example.com"
                    inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoPredictiveText
                }
                RowLayout {
                    Kirigami.FormData.label: i18n("API token:")
                    spacing: Kirigami.Units.smallSpacing
                    TextField {
                        id: token2Field
                        Layout.fillWidth: true
                        echoMode: showToken2Check.checked ? TextInput.Normal : TextInput.Password
                        placeholderText: i18n("Generado en id.atlassian.com")
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                    }
                    CheckBox { id: showToken2Check; text: i18n("Ver") }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                enabled: jira2EnabledCheck.checked
                Button {
                    text: i18n("Probar")
                    icon.name: "network-connect"
                    onClicked: {
                        status2Label.text = i18n("Conectando…");
                        status2Label.color = palette.text;
                        page._test(site2Field.text, email2Field.text, token2Field.text, status2Label);
                    }
                }
                Item { Layout.fillWidth: true }
            }
            Label {
                id: status2Label
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: ""
            }
        }
    }

    Item { Layout.fillHeight: true }

    // Shared palette popup for the block-color swatches.
    Popup {
        id: colorPopup
        modal: true
        focus: true
        padding: 8
        Grid {
            columns: 6
            spacing: 6
            Repeater {
                model: page._palette
                delegate: Rectangle {
                    width: 28; height: 28; radius: 4
                    color: modelData
                    property string _cur: page._colorTarget === 2 ? page.cfg_jira2BlockColor
                                                                   : page.cfg_jira1BlockColor
                    border.width: _cur === modelData ? 2 : 1
                    border.color: _cur === modelData ? Kirigami.Theme.highlightColor
                                                     : Qt.rgba(1, 1, 1, 0.4)
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (page._colorTarget === 2) page.cfg_jira2BlockColor = modelData;
                            else                         page.cfg_jira1BlockColor = modelData;
                            colorPopup.close();
                        }
                    }
                }
            }
        }
    }

    function _test(site, email, token, lbl) {
        site = (site || "").trim().replace(/\/+$/, "");
        if (!site || !email || !token) {
            lbl.text = i18n("Completá los tres campos antes de probar.");
            lbl.color = "#e74c3c";
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", site + "/rest/api/3/myself", true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(email + ":" + token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    lbl.text = i18n("OK — autenticado como %1", d.displayName || email);
                    lbl.color = "#2ecc71";
                } catch (e) {
                    lbl.text = i18n("OK (servidor respondió 200).");
                    lbl.color = "#2ecc71";
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                lbl.text = i18n("Credenciales rechazadas (HTTP %1).", xhr.status);
                lbl.color = "#e74c3c";
            } else if (xhr.status === 0) {
                lbl.text = i18n("No se pudo contactar el servidor.");
                lbl.color = "#e74c3c";
            } else {
                var msg = xhr.responseText || xhr.statusText || "";
                lbl.text = i18n("HTTP %1: %2", xhr.status, msg.substring(0, 200));
                lbl.color = "#e74c3c";
            }
        };
        try { xhr.send(); }
        catch (e) {
            lbl.text = i18n("Error de red: %1", e);
            lbl.color = "#e74c3c";
        }
    }
}
