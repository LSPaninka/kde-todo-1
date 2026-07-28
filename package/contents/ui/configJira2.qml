/*
 * configJira2.qml - "Jira 2" tab of the configuration dialog. Identical to
 * configJira.qml but bound to the jira2* KCfg entries (second instance).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property alias  cfg_jira2Site:            siteField.text
    property alias  cfg_jira2Email:           emailField.text
    property alias  cfg_jira2Token:           tokenField.text
    property alias  cfg_jira2Jql:             jqlField.text
    property alias  cfg_jira2RefreshMinutes:  refreshSpin.value
    property alias  cfg_jira2MaxResults:      maxSpin.value
    property alias  cfg_jira2CategoryCount:   catCountSpin.value
    property alias  cfg_jira2SprintField:     sprintFieldField.text
    property alias  cfg_jira2ShowHuTab:       huTabCheck.checked
    property alias  cfg_jira2Debug:           debugCheck.checked

    Kirigami.FormLayout {
        Layout.fillWidth: true

        TextField {
            id: siteField
            Kirigami.FormData.label: i18n("Sitio Jira 2:")
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

        TextField {
            id: jqlField
            Kirigami.FormData.label: i18n("JQL:")
            Layout.fillWidth: true
            placeholderText: "assignee = currentUser() AND statusCategory != Done"
        }

        SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Auto-refresh (min):")
            from: 0
            to: 1440
            stepSize: 1
        }

        SpinBox {
            id: maxSpin
            Kirigami.FormData.label: i18n("Máx. resultados:")
            from: 10
            to: 200
            stepSize: 10
        }

        SpinBox {
            id: catCountSpin
            Kirigami.FormData.label: i18n("Categorías Jira 2 (pestañas):")
            from: 1
            to: 10
            stepSize: 1
        }

        TextField {
            id: sprintFieldField
            Kirigami.FormData.label: i18n("Campo de Sprint:")
            Layout.fillWidth: true
            placeholderText: "customfield_10020"
            inputMethodHints: Qt.ImhNoPredictiveText
        }

        CheckBox {
            id: huTabCheck
            Kirigami.FormData.label: i18n("Pestaña HU:")
            text: i18n("Mostrar la pestaña «HU» (historias de usuario / padres de las subtareas)")
        }

        CheckBox {
            id: debugCheck
            Kirigami.FormData.label: i18n("Logs de depuración:")
            text: i18n("Loggear fetch/parse/filter en plasmashell stdout")
        }
    }

    // -------- Test connection --------
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

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: i18n(
            "Segunda instancia de Jira, con sus propias credenciales. El token se "
          + "guarda en texto plano en ~/.config/plasma-org.kde.plasma.desktop-appletsrc. "
          + "Crealo en https://id.atlassian.com/manage-profile/security/api-tokens.")
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
        catch (e) { statusLabel.text = i18n("Error de red: %1", e); statusLabel.color = "#e74c3c"; }
    }
}
