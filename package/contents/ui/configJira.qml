/*
 * configJira.qml - Jira tab of the configuration dialog.
 *
 *   - Site URL (https://your-site.atlassian.net)
 *   - Email (the address registered with Atlassian)
 *   - API token (NOT password). Created at id.atlassian.com.
 *   - JQL query for the issues to display.
 *   - Refresh interval and max results.
 *   - "Test connection" button that hits /rest/api/3/myself.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Plasma 6 also assigns cfg_<key>Default; declare them to avoid warnings.
    property var cfg_jiraSiteDefault
    property var cfg_jiraEmailDefault
    property var cfg_jiraTokenDefault
    property var cfg_jiraJqlDefault
    property var cfg_jiraRefreshMinutesDefault
    property var cfg_jiraMaxResultsDefault
    property var cfg_jiraCategoryCountDefault
    property var cfg_jiraSprintFieldDefault
    property var cfg_jiraShowHuTabDefault
    property var cfg_jiraShowHechasTabDefault
    property var cfg_jiraDebugDefault
    property var cfg_jiraRemainingModeDefault

    // Auto-bound to KCfg entries:
    property alias  cfg_jiraSite:            siteField.text
    property alias  cfg_jiraEmail:           emailField.text
    property alias  cfg_jiraToken:           tokenField.text
    property alias  cfg_jiraJql:             jqlField.text
    property alias  cfg_jiraRefreshMinutes:  refreshSpin.value
    property alias  cfg_jiraMaxResults:      maxSpin.value
    property alias  cfg_jiraCategoryCount:   catCountSpin.value
    property alias  cfg_jiraSprintField:     sprintFieldField.text
    property alias  cfg_jiraShowHuTab:       huTabCheck.checked
    property alias  cfg_jiraShowHechasTab:   hechasTabCheck.checked
    property alias  cfg_jiraDebug:           debugCheck.checked

    // Scalar string bound manually via the ComboBox below (see onActivated).
    property string cfg_jiraRemainingMode: "calculated"

    // -------- Test machinery --------
    // Basic-auth header value. Base64 of the UTF-8 bytes of "user:pass"
    // (Qt 6 deprecates Qt.btoa(string), so it's done by hand).
    function _basicAuth(user, pass) {
        var s = unescape(encodeURIComponent(user + ":" + pass));
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        var out = "";
        for (var i = 0; i < s.length; i += 3) {
            var n = (s.charCodeAt(i) << 16) | ((s.charCodeAt(i + 1) || 0) << 8) | (s.charCodeAt(i + 2) || 0);
            out += chars[(n >> 18) & 63] + chars[(n >> 12) & 63]
                 + (i + 1 < s.length ? chars[(n >> 6) & 63] : "=")
                 + (i + 2 < s.length ? chars[n & 63] : "=");
        }
        return "Basic " + out;
    }

    function _test(site, email, token) {
        site = (site || "").trim().replace(/\/+$/, "");
        if (!site || !email || !token) {
            statusLabel.text = i18n("Completá los tres campos antes de probar.");
            statusLabel.color = "#e74c3c";
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", site + "/rest/api/3/myself", true);
        xhr.setRequestHeader("Authorization", _basicAuth(email, token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    statusLabel.text = i18n("OK — autenticado como %1",
                                            d.displayName || email);
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
        try {
            xhr.send();
        } catch (e) {
            statusLabel.text = i18n("Error de red: %1", e);
            statusLabel.color = "#e74c3c";
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

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
                // 0 disables the timer; the user can still refresh manually.
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
                Kirigami.FormData.label: i18n("Categorías Jira (pestañas):")
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

            ComboBox {
                id: remainingModeCombo
                Kirigami.FormData.label: i18n("Horas restantes:")
                Layout.fillWidth: true
                textRole: "text"
                model: [
                    { value: "calculated", text: i18n("Calculado (original - consumido)") },
                    { value: "api",        text: i18n("Estimación de Jira (remaining)") }
                ]
                onActivated: page.cfg_jiraRemainingMode = model[currentIndex].value
                Component.onCompleted:
                    currentIndex = (page.cfg_jiraRemainingMode === "api") ? 1 : 0
            }

            CheckBox {
                id: huTabCheck
                Kirigami.FormData.label: i18n("Pestaña HU:")
                text: i18n("Mostrar la pestaña «HU» (historias de usuario / padres de las subtareas)")
            }

            CheckBox {
                id: hechasTabCheck
                Kirigami.FormData.label: i18n("Pestaña Hechas:")
                text: i18n("Mostrar la pestaña «Hechas» (mis subtareas finalizadas)")
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
                        id: testBtn
                        text: i18n("Probar")
                        icon.name: "network-connect"
                        onClicked: {
                            statusLabel.text = i18n("Conectando…");
                            statusLabel.color = palette.text;
                            // Use the values currently entered, which may not
                            // be saved yet; that's the whole point of the test.
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

        // -------- Help --------
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n(
                "El token se guarda en texto plano dentro de "
              + "~/.config/plasma-org.kde.plasma.desktop-appletsrc (sólo lectura "
              + "para tu usuario). Crealo en https://id.atlassian.com/manage-profile/security/api-tokens "
              + "y revocálo si dejás de usar el plasmoide. Ver docs/JIRA.md para más detalles.")
        }

        Item { Layout.fillHeight: true }

    }
}
