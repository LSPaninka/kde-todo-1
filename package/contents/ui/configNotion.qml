/*
 * configNotion.qml - Notion tab of the configuration dialog.
 *
 * Notion is integrated into the ToDo mode as a two-way sync over the
 * official HTTP API (the old `ntn` CLI mode is disabled). Here the user
 * pastes an internal integration token + a parent page id and presses
 * "Crear base de datos" once to bootstrap the Notion database. From then
 * on the ToDo popup syncs automatically (and via its Notion button).
 *
 * The token/database id are auto-bound KCfg entries. The "Test" and
 * "Create database" buttons issue their own XMLHttpRequest calls (same
 * pattern as configJira.qml) so they work with the currently-typed values
 * before the dialog is even saved.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property alias  cfg_notionApiToken:       tokenField.text
    property alias  cfg_notionParentPageId:   parentField.text
    property alias  cfg_notionDatabaseId:     dbField.text
    property alias  cfg_notionRefreshMinutes: refreshSpin.value
    property alias  cfg_notionSyncOnOpen:     syncOnOpenCheck.checked
    property alias  cfg_notionDebug:          debugCheck.checked

    readonly property string _apiBase: "https://api.notion.com/v1"
    readonly property string _notionVersion: "2022-06-28"

    // Notion IDs are 32 hex chars, often pasted as a full URL or dashed UUID.
    // Pull the last 32-hex run out of whatever the user pasted.
    function _extractId(s) {
        s = String(s || "");
        var compact = s.replace(/-/g, "");
        var m = compact.match(/[0-9a-fA-F]{32}(?![0-9a-fA-F])/g);
        if (m && m.length) return m[m.length - 1];
        return s.trim();
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.8
        text: i18n("El modo ToDo puede sincronizarse con una base de datos de Notion (ida y vuelta). "
                 + "1) Creá una integración interna en https://www.notion.so/my-integrations y copiá "
                 + "su token secreto. 2) Compartí una página con esa integración y pegá su ID como "
                 + "«página padre». 3) Pulsá «Crear base de datos» una vez. Desde entonces la lista se "
                 + "sincroniza al abrir el plasmoide y con el botón «Notion» del popup.")
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        RowLayout {
            Kirigami.FormData.label: i18n("Token de integración:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: tokenField
                Layout.fillWidth: true
                echoMode: showTokenCheck.checked ? TextInput.Normal : TextInput.Password
                placeholderText: "secret_… / ntn_…"
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            }
            CheckBox {
                id: showTokenCheck
                text: i18n("Ver")
            }
        }

        TextField {
            id: parentField
            Kirigami.FormData.label: i18n("Página padre (ID o URL):")
            Layout.fillWidth: true
            placeholderText: i18n("Pegá la URL o el ID de la página compartida con la integración")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Base de datos:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: dbField
                Layout.fillWidth: true
                placeholderText: i18n("Se completa al crear la base (o pegá una existente)")
            }
            Label {
                text: dbField.text.length > 0 ? i18n("✓ configurada") : i18n("sin configurar")
                opacity: 0.7
            }
        }

        SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: i18n("Auto-sync (min):")
            from: 0
            to: 1440
            stepSize: 1
        }

        CheckBox {
            id: syncOnOpenCheck
            Kirigami.FormData.label: i18n("Al abrir:")
            text: i18n("Sincronizar con Notion cada vez que se abre el plasmoide")
        }

        CheckBox {
            id: debugCheck
            Kirigami.FormData.label: i18n("Logs:")
            text: i18n("Loggear las llamadas a la API de Notion en plasmashell")
        }
    }

    // -------- Actions --------
    GroupBox {
        Layout.fillWidth: true
        title: i18n("Configurar Notion")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Button {
                    text: i18n("Probar token")
                    icon.name: "network-connect"
                    onClicked: {
                        statusLabel.text = i18n("Conectando…");
                        statusLabel.color = palette.text;
                        page._testToken(tokenField.text);
                    }
                }

                Button {
                    text: i18n("Crear base de datos")
                    icon.name: "list-add"
                    enabled: tokenField.text.length > 0 && parentField.text.length > 0
                    onClicked: {
                        statusLabel.text = i18n("Creando base de datos en Notion…");
                        statusLabel.color = palette.text;
                        page._createDatabase(tokenField.text, page._extractId(parentField.text));
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
        opacity: 0.65
        text: i18n("La sincronización es de doble vía: lo nuevo en cualquier lado se crea en el otro, "
                 + "y si una tarea cambió en ambos lados gana la edición más reciente. No se borran "
                 + "tareas automáticamente. Ver docs/NOTION.md.")
    }

    Item { Layout.fillHeight: true }

    // -------- HTTP helpers --------
    function _testToken(token) {
        token = (token || "").trim();
        if (!token) {
            statusLabel.text = i18n("Pegá el token antes de probar.");
            statusLabel.color = "#e74c3c";
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", _apiBase + "/users/me", true);
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.setRequestHeader("Notion-Version", _notionVersion);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    statusLabel.text = i18n("OK — integración «%1» autenticada.", d.name || "bot");
                    statusLabel.color = "#2ecc71";
                } catch (e) {
                    statusLabel.text = i18n("OK (200).");
                    statusLabel.color = "#2ecc71";
                }
            } else if (xhr.status === 401) {
                statusLabel.text = i18n("Token rechazado (HTTP 401).");
                statusLabel.color = "#e74c3c";
            } else if (xhr.status === 0) {
                statusLabel.text = i18n("No se pudo contactar api.notion.com.");
                statusLabel.color = "#e74c3c";
            } else {
                statusLabel.text = i18n("HTTP %1: %2", xhr.status,
                                        (xhr.responseText || "").substring(0, 200));
                statusLabel.color = "#e74c3c";
            }
        };
        try { xhr.send(); }
        catch (e) { statusLabel.text = i18n("Error de red: %1", e); statusLabel.color = "#e74c3c"; }
    }

    function _createDatabase(token, parentId) {
        token = (token || "").trim();
        if (!token || !parentId) {
            statusLabel.text = i18n("Completá token y página padre.");
            statusLabel.color = "#e74c3c";
            return;
        }
        var body = {
            parent: { type: "page_id", page_id: parentId },
            title: [ { type: "text", text: { content: "Categorized ToDo" } } ],
            properties: {
                "Name":        { title: {} },
                "Description": { rich_text: {} },
                "Category":    { number: {} },
                "Priority":    { select: { options: [
                                    { name: "XS" }, { name: "S" }, { name: "M" },
                                    { name: "L" }, { name: "XL" } ] } },
                "Done":        { checkbox: {} },
                "Archived":    { checkbox: {} },
                "Subtasks":    { rich_text: {} },
                "LocalId":     { number: {} }
            }
        };
        var xhr = new XMLHttpRequest();
        xhr.open("POST", _apiBase + "/databases", true);
        xhr.setRequestHeader("Authorization", "Bearer " + token);
        xhr.setRequestHeader("Notion-Version", _notionVersion);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var json = null;
            try { json = JSON.parse(xhr.responseText); } catch (e) {}
            if (xhr.status >= 200 && xhr.status < 300 && json && json.id) {
                dbField.text = json.id;   // bound to cfg_notionDatabaseId
                statusLabel.text = i18n("Base creada. Guardá con «Aplicar». Ya podés sincronizar desde el popup.");
                statusLabel.color = "#2ecc71";
            } else {
                var m = (json && json.message) ? json.message : ("HTTP " + xhr.status);
                statusLabel.text = i18n("No se pudo crear: %1", m);
                statusLabel.color = "#e74c3c";
            }
        };
        try { xhr.send(JSON.stringify(body)); }
        catch (e) { statusLabel.text = i18n("Error de red: %1", e); statusLabel.color = "#e74c3c"; }
    }
}
