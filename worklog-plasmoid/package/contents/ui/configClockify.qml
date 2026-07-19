/*
 * configClockify.qml - Clockify tab.
 *
 * Auth via the X-Api-Key header. Generate the key at
 * https://app.clockify.me/user/settings → API. The plasmoid will resolve
 * workspaceId + userId on first sync via GET /user and cache them.
 *
 * "Probar conexión" validates the key AND fetches the workspace's projects
 * so the default project can be picked from a ComboBox instead of pasting
 * a hex id by hand.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property alias  cfg_clockifyApiKey:           keyField.text
    property alias  cfg_clockifyWorkspaceId:      workspaceField.text
    property string cfg_clockifyDefaultProjectId: ""
    property alias  cfg_clockifyBillableDefault:  billableCheck.checked

    // Jira → Clockify sync mapping: which Clockify project each Jira
    // instance's worklogs are copied into (keeps the two from overlapping).
    property string cfg_jira1ClockifyProjectId: ""
    property string cfg_jira2ClockifyProjectId: ""

    // Projects fetched by "Probar". Always starts with "(sin proyecto)".
    property var projectList: [{ id: "", name: i18n("(sin proyecto)") }]

    function _projectIndexFor(id) {
        for (var i = 0; i < projectList.length; i++) {
            if (projectList[i].id === id) return i;
        }
        return -1;
    }
    // Model for a project combo: the fetched list + a placeholder row for a
    // saved id that isn't in the list yet (so it's not silently dropped).
    function _projModel(savedId) {
        var arr = page.projectList.slice();
        if (savedId && page._projectIndexFor(savedId) < 0) {
            arr.push({ id: savedId, name: i18n("[%1] (probá la conexión)", savedId.substring(0, 8)) });
        }
        return arr;
    }
    function _projIndexIn(model, id) {
        for (var i = 0; i < model.length; i++) if (model[i].id === id) return i;
        return 0;
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Clockify se autentica con un API key personal. Generalo en "
                 + "Clockify → Perfil → Settings → API y pegalo abajo. El plasmoide "
                 + "resuelve usuario + workspace automáticamente en la primera sincronización.")
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        RowLayout {
            Kirigami.FormData.label: i18n("API key:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: keyField
                Layout.fillWidth: true
                echoMode: showKey.checked ? TextInput.Normal : TextInput.Password
                placeholderText: i18n("Pegá tu API key acá")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            }
            CheckBox {
                id: showKey
                text: i18n("Ver")
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Workspace ID:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: workspaceField
                Layout.fillWidth: true
                placeholderText: i18n("Vacío = usa tu workspace por defecto")
                inputMethodHints: Qt.ImhNoPredictiveText
            }
            Button {
                text: i18n("Limpiar")
                icon.name: "edit-clear"
                enabled: workspaceField.text.length > 0
                onClicked: workspaceField.text = ""
                ToolTip.text: i18n("Vaciar el campo para que el plasmoide use el workspace por defecto")
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }
        }

        Label {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.65
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            text: i18n("Es un Object ID hex de 24 caracteres (ej. 60661036c145ea559a4e8be6), no "
                     + "el nombre del workspace. Si lo dejás vacío, el plasmoide va a resolver "
                     + "tu workspace por defecto en la primera sincronización.")
        }

        // Default project — ComboBox populated by "Probar". Before that it
        // only has "(sin proyecto)" plus, if a project id is already saved,
        // a placeholder row so the saved value isn't silently dropped.
        ComboBox {
            id: projectCombo
            Kirigami.FormData.label: i18n("Proyecto por defecto:")
            Layout.fillWidth: true
            textRole: "name"
            valueRole: "id"
            model: {
                var arr = page.projectList.slice();
                var id = page.cfg_clockifyDefaultProjectId;
                if (id && page._projectIndexFor(id) < 0) {
                    arr.push({ id: id, name: i18n("[%1] (probá la conexión)", id.substring(0, 8)) });
                }
                return arr;
            }
            currentIndex: {
                var i = _modelIndexFor(page.cfg_clockifyDefaultProjectId);
                return i < 0 ? 0 : i;
            }
            onActivated: page.cfg_clockifyDefaultProjectId = model[currentIndex].id
            function _modelIndexFor(id) {
                for (var i = 0; i < model.length; i++) {
                    if (model[i].id === id) return i;
                }
                return -1;
            }
        }

        CheckBox {
            id: billableCheck
            Kirigami.FormData.label: i18n("Billable:")
            text: i18n("Marcar como facturable por defecto en nuevas entradas")
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
                        page._test(keyField.text);
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

    // -------- Jira → Clockify sync mapping --------
    GroupBox {
        Layout.fillWidth: true
        title: i18n("Sync Jira → Clockify")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.75
                text: i18n("Al usar el botón «Jira → Clockify», cada instancia de Jira copia sus "
                         + "worklogs al proyecto elegido acá. Así no se solapan ni se cargan en el "
                         + "proyecto equivocado. Probá la conexión arriba para poblar la lista.")
            }

            Kirigami.FormLayout {
                Layout.fillWidth: true

                ComboBox {
                    id: jira1ProjCombo
                    Kirigami.FormData.label: i18n("Jira 1 →:")
                    Layout.fillWidth: true
                    textRole: "name"
                    valueRole: "id"
                    model: page._projModel(page.cfg_jira1ClockifyProjectId)
                    currentIndex: page._projIndexIn(model, page.cfg_jira1ClockifyProjectId)
                    onActivated: page.cfg_jira1ClockifyProjectId = model[currentIndex].id
                }
                ComboBox {
                    id: jira2ProjCombo
                    Kirigami.FormData.label: i18n("Jira 2 →:")
                    Layout.fillWidth: true
                    textRole: "name"
                    valueRole: "id"
                    model: page._projModel(page.cfg_jira2ClockifyProjectId)
                    currentIndex: page._projIndexIn(model, page.cfg_jira2ClockifyProjectId)
                    onActivated: page.cfg_jira2ClockifyProjectId = model[currentIndex].id
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    // -------- Connection test + project fetch --------

    function _test(key) {
        key = (key || "").trim();
        if (!key) {
            statusLabel.text = i18n("Pegá una API key antes de probar.");
            statusLabel.color = "#e74c3c";
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.clockify.me/api/v1/user", true);
        xhr.setRequestHeader("X-Api-Key", key);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    statusLabel.text = i18n("OK — autenticado como %1. Cargando proyectos…",
                                            d.name || d.email || "?");
                    statusLabel.color = "#2ecc71";
                    var wid = workspaceField.text.trim();
                    if (!/^[0-9a-fA-F]{24}$/.test(wid)) {
                        wid = d.defaultWorkspace || d.activeWorkspace || "";
                    }
                    if (wid) page._fetchProjects(key, wid);
                    else statusLabel.text = i18n("OK, pero no pude resolver el workspace.");
                } catch (e) {
                    statusLabel.text = i18n("OK (200) pero respuesta inesperada.");
                    statusLabel.color = "#2ecc71";
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                statusLabel.text = i18n("Credenciales rechazadas (HTTP %1).", xhr.status);
                statusLabel.color = "#e74c3c";
            } else if (xhr.status === 0) {
                statusLabel.text = i18n("No se pudo contactar el servidor.");
                statusLabel.color = "#e74c3c";
            } else {
                statusLabel.text = i18n("HTTP %1: %2", xhr.status,
                                         (xhr.responseText || "").substring(0, 200));
                statusLabel.color = "#e74c3c";
            }
        };
        try { xhr.send(); }
        catch (e) {
            statusLabel.text = i18n("Error de red: %1", e);
            statusLabel.color = "#e74c3c";
        }
    }

    function _fetchProjects(key, wid) {
        var url = "https://api.clockify.me/api/v1/workspaces/" + wid +
                  "/projects?archived=false&page-size=200";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.setRequestHeader("X-Api-Key", key);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) {
                statusLabel.text = i18n("Conexión OK, pero falló al traer proyectos (HTTP %1).", xhr.status);
                statusLabel.color = "#e67e22";
                return;
            }
            try {
                var raw = JSON.parse(xhr.responseText);
                var arr = [{ id: "", name: i18n("(sin proyecto)") }];
                for (var i = 0; i < raw.length; i++) {
                    arr.push({ id: raw[i].id || "", name: raw[i].name || "(sin nombre)" });
                }
                page.projectList = arr;
                statusLabel.text = i18n("OK — %1 proyecto(s) disponibles. Elegí el proyecto por defecto arriba.",
                                        raw.length);
                statusLabel.color = "#2ecc71";
            } catch (e) {
                statusLabel.text = i18n("Conexión OK, pero no pude parsear la lista de proyectos.");
                statusLabel.color = "#e67e22";
            }
        };
        try { xhr.send(); }
        catch (e) {
            statusLabel.text = i18n("Error de red al traer proyectos: %1", e);
            statusLabel.color = "#e74c3c";
        }
    }
}
