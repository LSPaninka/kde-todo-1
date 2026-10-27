/*
 * configTrelloLists.qml - "Listas Trello" tab of the configuration dialog.
 *
 * Loads the open lists of the configured board and lets the user, per list:
 *   - show / hide it (hidden lists get no tab and no panel swatch),
 *   - pick its color (tab dot, panel swatch, checklist bar),
 *   - pick the panel counter text color (white / black).
 *
 * Stored by list id (so renaming / reordering lists in Trello keeps the
 * settings) as StringLists: trelloHiddenLists = [id, …],
 * trelloListColors / trelloListTextColors = ["id=value", …]. Written straight
 * to Plasmoid.configuration (a reassigned `var` StringList doesn't persist
 * reliably through Apply — Plasma quirk).
 *
 * Uses the *applied* key / token / board from the "Trello" tab.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs as Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    property var _lists: []
    property int _rev: 0
    property string _status: ""
    property bool _statusError: false

    // Same default palette as TrelloStore.
    readonly property var _palette: ["#0079bf", "#d29034", "#519839", "#b04632",
                                     "#89609e", "#cd5a91", "#4bbf6b", "#00aecc",
                                     "#838c91", "#e6c60d"]

    function _boardRef() {
        var s = (Plasmoid.configuration.trelloBoard || "").trim();
        var m = s.match(/trello\.com\/b\/([A-Za-z0-9]+)/);
        if (m) return m[1];
        return s.replace(/[^A-Za-z0-9]/g, "");
    }

    function _load() {
        var key = (Plasmoid.configuration.trelloApiKey || "").trim();
        var token = (Plasmoid.configuration.trelloToken || "").trim();
        var board = _boardRef();
        if (!key || !token || !board) {
            _statusError = true;
            _status = i18n("Configurá y aplicá la API key, el token y el tablero en la pestaña «Trello».");
            return;
        }
        _statusError = false;
        _status = i18n("Cargando listas…");
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.trello.com/1/boards/" + encodeURIComponent(board) +
                        "/lists?filter=open&fields=id,name,pos", true);
        xhr.setRequestHeader("Authorization",
            'OAuth oauth_consumer_key="' + key + '", oauth_token="' + token + '"');
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var arr = JSON.parse(xhr.responseText) || [];
                    arr.sort(function(a, b) { return a.pos - b.pos; });
                    page._lists = arr;
                    page._status = i18np("%1 lista.", "%1 listas.", arr.length);
                } catch (e) {
                    page._statusError = true;
                    page._status = i18n("Respuesta inválida: %1", e);
                }
            } else {
                page._statusError = true;
                page._status = xhr.status === 0
                    ? i18n("No se pudo contactar api.trello.com.")
                    : i18n("HTTP %1: %2", xhr.status, (xhr.responseText || "").substring(0, 200));
            }
        };
        try { xhr.send(); } catch (e) { _statusError = true; _status = i18n("Error de red: %1", e); }
    }

    Component.onCompleted: _load()

    // ----- "id=value" StringList helpers -----
    function _mapGet(key, id) {
        var arr = (page._rev, Plasmoid.configuration[key] || []);
        var p = id + "=";
        for (var i = 0; i < arr.length; i++) {
            var s = String(arr[i]);
            if (s.indexOf(p) === 0) return s.substring(p.length);
        }
        return "";
    }
    function _mapSet(key, id, value) {
        var arr = (Plasmoid.configuration[key] || []).slice();
        var p = id + "=";
        arr = arr.filter(function(s) { return String(s).indexOf(p) !== 0; });
        if (value) arr.push(p + value);
        Plasmoid.configuration[key] = arr;
        page._rev++;
    }

    function _isHidden(id) {
        return (page._rev, Plasmoid.configuration.trelloHiddenLists || []).indexOf(id) >= 0;
    }
    function _setHidden(id, hidden) {
        var arr = (Plasmoid.configuration.trelloHiddenLists || []).filter(function(x) { return x !== id; });
        if (hidden) arr.push(id);
        Plasmoid.configuration.trelloHiddenLists = arr;
        page._rev++;
    }

    function _color(id, index) {
        return _mapGet("trelloListColors", id) || _palette[index % _palette.length];
    }

    Dialogs.ColorDialog {
        id: colorDlg
        property string targetId: ""
        title: i18n("Elegí un color")
        onAccepted: page._mapSet("trelloListColors", targetId, selectedColor.toString())
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Label {
            Layout.fillWidth: true
            Layout.preferredWidth: 600
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: i18n("Cada lista abierta del tablero es una pestaña del popup y un cuadrado en el "
                     + "panel. Desmarcá las que no quieras ver y elegí su color.")
        }

        RowLayout {
            Layout.fillWidth: true
            Button {
                text: i18n("Recargar listas")
                icon.name: "view-refresh"
                onClicked: page._load()
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: page._status
                color: page._statusError ? "#e74c3c" : palette.text
                opacity: page._statusError ? 1.0 : 0.7
            }
        }

        // One row per list: [✓ show] name ........ [■ color] [↺] [counter text ▾]
        Repeater {
            model: page._lists
            delegate: RowLayout {
                id: listRow
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                readonly property string listId: modelData.id

                CheckBox {
                    checked: !page._isHidden(listRow.listId)
                    onToggled: page._setHidden(listRow.listId, !checked)
                    ToolTip.text: i18n("Mostrar esta lista (pestaña y cuadrado del panel)")
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                }
                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 160
                    text: modelData.name
                    elide: Text.ElideRight
                    opacity: page._isHidden(listRow.listId) ? 0.5 : 1.0
                }
                Rectangle {
                    id: swatch
                    width: 28
                    height: 28
                    radius: 4
                    color: page._color(listRow.listId, index)
                    border.color: Qt.darker(color, 1.5)
                    border.width: 1
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            colorDlg.targetId = listRow.listId;
                            colorDlg.selectedColor = swatch.color;
                            colorDlg.open();
                        }
                    }
                }
                ToolButton {
                    icon.name: "edit-undo"
                    enabled: page._mapGet("trelloListColors", listRow.listId) !== ""
                    onClicked: page._mapSet("trelloListColors", listRow.listId, "")
                    ToolTip.text: i18n("Volver al color por defecto")
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                }
                ComboBox {
                    model: [i18n("Contador blanco"), i18n("Contador negro")]
                    currentIndex: page._mapGet("trelloListTextColors", listRow.listId) === "black" ? 1 : 0
                    onActivated: (i) => page._mapSet("trelloListTextColors", listRow.listId, i === 1 ? "black" : "")
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
