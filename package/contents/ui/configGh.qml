/*
 * configGh.qml - "GitHub" tab of the configuration dialog.
 *
 *   - Personal Access Token (classic: project,read:org,repo / fine-grained: Projects read).
 *   - Owner (user/org login) + owner type + project number.
 *   - Name of the field that drives the per-category "status" filter
 *     (defaults to "Status").
 *   - Refresh interval / max results.
 *   - "Test token" button that hits /user.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property alias  cfg_ghToken:           tokenField.text
    property alias  cfg_ghOwner:           ownerField.text
    property string cfg_ghOwnerType:       "user"
    property alias  cfg_ghProjectNumber:   projectSpin.value
    property alias  cfg_ghStatusField:     statusFieldField.text
    property alias  cfg_ghIncludeClosed:   includeClosedCheck.checked
    property alias  cfg_ghRefreshMinutes:  refreshSpin.value
    property alias  cfg_ghMaxResults:      maxSpin.value
    property alias  cfg_ghCategoryCount:   catCountSpin.value
    property alias  cfg_ghDebug:           debugCheck.checked

    Kirigami.FormLayout {
        Layout.fillWidth: true

        RowLayout {
            Kirigami.FormData.label: i18n("Personal Access Token:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: tokenField
                Layout.fillWidth: true
                echoMode: showTokenCheck.checked ? TextInput.Normal : TextInput.Password
                placeholderText: i18n("ghp_… (classic) o github_pat_… (fine-grained)")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            }
            CheckBox {
                id: showTokenCheck
                text: i18n("Ver")
            }
        }

        TextField {
            id: ownerField
            Kirigami.FormData.label: i18n("Owner (usuario u org):")
            Layout.fillWidth: true
            placeholderText: "octocat"
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Tipo de owner:")
            ButtonGroup { id: ownerTypeGroup }
            RadioButton {
                ButtonGroup.group: ownerTypeGroup
                text: i18n("Usuario")
                checked: page.cfg_ghOwnerType !== "organization"
                onToggled: if (checked) page.cfg_ghOwnerType = "user"
            }
            RadioButton {
                ButtonGroup.group: ownerTypeGroup
                text: i18n("Organización")
                checked: page.cfg_ghOwnerType === "organization"
                onToggled: if (checked) page.cfg_ghOwnerType = "organization"
            }
        }

        SpinBox {
            id: projectSpin
            Kirigami.FormData.label: i18n("Número de proyecto:")
            from: 1
            to: 99999
            stepSize: 1
        }

        TextField {
            id: statusFieldField
            Kirigami.FormData.label: i18n("Campo de estado:")
            Layout.fillWidth: true
            placeholderText: "Status"
        }

        CheckBox {
            id: includeClosedCheck
            Kirigami.FormData.label: i18n("Cerrados:")
            text: i18n("Incluir issues cerrados y PRs mergeados")
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
            to: 300
            stepSize: 10
        }

        SpinBox {
            id: catCountSpin
            Kirigami.FormData.label: i18n("Categorías GH (pestañas):")
            from: 1
            to: 4
            stepSize: 1
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
                    text: i18n("Probar token")
                    icon.name: "network-connect"
                    onClicked: {
                        statusLabel.text = i18n("Conectando…");
                        statusLabel.color = palette.text;
                        page._test(tokenField.text);
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
            "Generá un token en https://github.com/settings/tokens. Para PATs «classic» "
          + "necesitás los scopes 'project', 'read:org' y 'repo'. Para PATs «fine-grained» "
          + "(beta), permitile leer Projects (organization permissions → Projects: Read) y, "
          + "para que los títulos de issues / PRs se vean, dale también lectura a Issues / "
          + "Pull requests de los repos que querés ver. El token se guarda en texto plano "
          + "dentro de ~/.config/plasma-org.kde.plasma.desktop-appletsrc.")
    }

    Item { Layout.fillHeight: true }

    function _test(token) {
        token = (token || "").trim();
        if (!token) {
            statusLabel.text = i18n("Completá el token antes de probar.");
            statusLabel.color = "#e74c3c";
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.github.com/user", true);
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.setRequestHeader("Accept", "application/vnd.github+json");
        xhr.setRequestHeader("User-Agent", "kde-categorizedtodo-plasmoid");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    statusLabel.text = i18n("OK — autenticado como %1", d.login || "?");
                    statusLabel.color = "#2ecc71";
                } catch (e) {
                    statusLabel.text = i18n("OK (servidor respondió 200).");
                    statusLabel.color = "#2ecc71";
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                statusLabel.text = i18n("Credenciales rechazadas (HTTP %1).", xhr.status);
                statusLabel.color = "#e74c3c";
            } else if (xhr.status === 0) {
                statusLabel.text = i18n("No se pudo contactar api.github.com.");
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
}
