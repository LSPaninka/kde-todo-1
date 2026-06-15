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
                        page._test(siteField.text, emailField.text, tokenField.text);
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

    Item { Layout.fillHeight: true }

    function _test(site, email, token) {
        site = (site || "").trim().replace(/\/+$/, "");
        if (!site || !email || !token) {
            statusLabel.text = i18n("Completá los tres campos antes de probar.");
            statusLabel.color = "#e74c3c";
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
                    statusLabel.text = i18n("OK — autenticado como %1", d.displayName || email);
                    statusLabel.color = "#2ecc71";
                } catch (e) {
                    statusLabel.text = i18n("OK (servidor respondió 200).");
                    statusLabel.color = "#2ecc71";
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                statusLabel.text = i18n("Credenciales rechazadas (HTTP %1).", xhr.status);
                statusLabel.color = "#e74c3c";
            } else if (xhr.status === 0) {
                statusLabel.text = i18n("No se pudo contactar el servidor.");
                statusLabel.color = "#e74c3c";
            } else {
                var msg = xhr.responseText || xhr.statusText || "";
                statusLabel.text = i18n("HTTP %1: %2", xhr.status, msg.substring(0, 200));
                statusLabel.color = "#e74c3c";
            }
        };
        try { xhr.send(); }
        catch (e) {
            statusLabel.text = i18n("Error de red: %1", e);
            statusLabel.color = "#e74c3c";
        }
    }
}
