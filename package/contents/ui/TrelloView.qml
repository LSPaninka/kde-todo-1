/*
 * TrelloView.qml - popup contents in "trello" mode.
 *
 * One tab per open (non-hidden) list of the configured board, in board
 * order. Below the tabs, a single text field that is quick-add by default
 * (Enter / "Agregar" creates a card in the current list, assigned to me) and
 * a live filter when the magnifier toggle in the header is on — the same UX
 * as the ToDo mode's category view. "Nueva…" opens the full modal.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: view
    property var trello
    property var plasmoidItem

    readonly property int _v: trello ? trello.version : 0

    // The visible lists drive two Repeaters (tabs + pages). Reassigning the
    // array rebuilds them (and can reset the selected tab), so it is only
    // replaced when the list structure really changes — not on every bump.
    property var _lists: []
    readonly property string _listsKey:
        (_v, Plasmoid.configuration.trelloHiddenLists, trello ? _keyOf(trello.visibleLists()) : "")
    on_ListsKeyChanged: _refreshLists()

    function _keyOf(arr) {
        return arr.map(function(l) { return l.id + ":" + l.name; }).join("|");
    }
    function _refreshLists() {
        var cur = _currentList();
        var curId = cur ? cur.id : "";
        _lists = trello ? trello.visibleLists() : [];
        for (var i = 0; curId && i < _lists.length; i++) {
            if (_lists[i].id === curId) { tabs.currentIndex = i; return; }
        }
    }

    readonly property int _listCount: _lists.length
    readonly property real _tabWidth:
        (view.width - 2 * Kirigami.Units.smallSpacing) / Math.max(1, _listCount)

    property bool _searchMode: false
    property string _status: ""
    property bool _statusError: false

    function _currentList() {
        var i = tabs.currentIndex;
        return (i >= 0 && i < _lists.length) ? _lists[i] : null;
    }

    function _filter(arr) {
        if (!_searchMode) return arr;
        var q = entryField.text.trim().toLowerCase();
        if (!q) return arr;
        var out = [];
        for (var i = 0; i < arr.length; i++) {
            var c = arr[i];
            var hay = (c.name || "") + " " + (c.desc || "");
            for (var j = 0; j < c.idLabels.length; j++) {
                var l = trello.labelById(c.idLabels[j]);
                if (l) hay += " " + l.name;
            }
            if (hay.toLowerCase().indexOf(q) >= 0) out.push(c);
        }
        return out;
    }

    function _quickAdd() {
        if (_searchMode || !trello) return;
        var t = entryField.text.trim();
        var l = _currentList();
        if (!t || !l) return;
        entryField.enabled = false;
        view._statusError = false;
        view._status = i18n("Creando tarjeta…");
        trello.createCard({
            idList: l.id,
            name: t,
            idMembers: trello.myId ? [trello.myId] : []
        }, function(ok, card, err) {
            entryField.enabled = true;
            if (ok) {
                entryField.text = "";
                view._status = "";
            } else {
                view._statusError = true;
                view._status = err;
            }
            entryField.forceActiveFocus();
        });
    }

    function _fmtDate(ms) {
        return ms ? Qt.formatDateTime(new Date(ms), Locale.ShortFormat) : "";
    }

    // Jump to the list requested from a panel swatch click.
    Connections {
        target: view.trello || null
        function onListRequested(index) {
            if (index >= 0 && index < view._listCount) tabs.currentIndex = index;
        }
    }
    Component.onCompleted: {
        _refreshLists();
        if (trello && trello.selectedList >= 0 && trello.selectedList < _listCount)
            tabs.currentIndex = trello.selectedList;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // -------- Header --------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "view-list-details"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            PlasmaComponents3.Label {
                text: (view._v, trello && trello.board && trello.board.name) ? trello.board.name : i18n("Trello")
                font.bold: true
                elide: Text.ElideRight
                Layout.maximumWidth: view.width * 0.4
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                opacity: 0.7
                color: (view._status ? view._statusError : (trello && trello.lastError))
                       ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                text: {
                    if (!trello) return "";
                    if (view._status) return view._status;
                    if (trello.loading) return i18n("Cargando…");
                    if (trello.lastError) return trello.lastError;
                    if (trello.lastFetchedAt > 0)
                        return i18n("Actualizado %1", view._fmtDate(trello.lastFetchedAt));
                    return "";
                }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: trello && !trello.loading
                onClicked: { view._status = ""; view._statusError = false; trello.fetch(); }
                PlasmaComponents3.ToolTip.text: i18n("Refrescar")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            // Toggle search vs. quick-add for the text field below the tabs.
            PlasmaComponents3.ToolButton {
                checkable: true
                checked: view._searchMode
                icon.name: "search"
                onToggled: {
                    view._searchMode = checked;
                    entryField.text = "";
                    entryField.forceActiveFocus();
                }
                PlasmaComponents3.ToolTip.text: view._searchMode
                        ? i18n("Volver a «crear tarjeta rápida»")
                        : i18n("Buscar tarjetas en esta lista")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.Button {
                icon.name: "document-new"
                text: i18n("Nueva…")
                enabled: view._listCount > 0
                onClicked: {
                    var l = view._currentList();
                    if (l) cardDialog.openNew(l.id);
                }
            }
        }

        // -------- Tabs: one per visible list --------
        QQC2.TabBar {
            id: tabs
            Layout.fillWidth: true
            visible: view._listCount > 0

            Repeater {
                model: view._lists
                QQC2.TabButton {
                    id: tabBtn
                    width: view._tabWidth
                    leftPadding: 6
                    rightPadding: 6
                    property int n: (view._v, Plasmoid.configuration.trelloOnlyMine,
                                     view.trello ? view.trello.countForList(modelData.id) : 0)
                    property color lc: (view._v, Plasmoid.configuration.trelloListColors,
                                        view.trello ? view.trello.listColor(modelData.id) : "#0079bf")
                    contentItem: RowLayout {
                        spacing: 6
                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            color: tabBtn.lc
                            Layout.alignment: Qt.AlignVCenter
                        }
                        PlasmaComponents3.Label {
                            text: modelData.name
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        TabCountBadge {
                            visible: tabBtn.n > 0
                            count: tabBtn.n
                            badgeColor: tabBtn.lc
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }

        // -------- Quick-add (default) / search (toggle) --------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: view._listCount > 0

            Kirigami.Icon {
                source: view._searchMode ? "search" : "list-add"
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
            }
            PlasmaComponents3.TextField {
                id: entryField
                Layout.fillWidth: true
                placeholderText: view._searchMode
                        ? i18n("Buscar tarjetas en esta lista…")
                        : i18n("Nueva tarjeta rápida… (Enter para crear)")
                onAccepted: view._quickAdd()
                Keys.onEscapePressed: text = ""
            }
            PlasmaComponents3.ToolButton {
                visible: view._searchMode && entryField.text.length > 0
                icon.name: "edit-clear"
                onClicked: entryField.text = ""
            }
            PlasmaComponents3.Button {
                visible: !view._searchMode
                icon.name: "list-add"
                text: i18n("Agregar")
                enabled: entryField.enabled && entryField.text.trim().length > 0
                onClicked: view._quickAdd()
            }
        }

        // -------- Body --------
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex
            visible: view._listCount > 0

            Repeater {
                model: view._lists
                Item {
                    property string listId: modelData.id
                    QQC2.ScrollView {
                        anchors.fill: parent
                        clip: true
                        ListView {
                            id: list
                            spacing: 6
                            model: (view._v, view._searchMode, entryField.text,
                                    Plasmoid.configuration.trelloOnlyMine,
                                    view.trello ? view._filter(view.trello.cardsForList(listId)) : [])
                            delegate: TrelloCardItem {
                                width: list.width
                                card: modelData
                                trello: view.trello
                                listColor: view.trello ? view.trello.listColor(listId) : "#0079bf"
                                onActivated: function(c) { cardDialog.openEdit(c); }
                            }

                            PlasmaComponents3.Label {
                                anchors.centerIn: parent
                                width: parent.width - 40
                                visible: list.count === 0 && view.trello && !view.trello.loading
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                opacity: 0.55
                                text: (view._searchMode && entryField.text.length > 0)
                                      ? i18n("Ninguna tarjeta coincide con la búsqueda.")
                                      : (Plasmoid.configuration.trelloOnlyMine !== false
                                         ? i18n("No tenés tarjetas en esta lista.")
                                         : i18n("Lista vacía."))
                            }
                        }
                    }
                }
            }
        }

        // -------- Empty / not configured --------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: view._listCount === 0
            spacing: Kirigami.Units.largeSpacing

            Item { Layout.fillHeight: true }
            PlasmaComponents3.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: view.trello && view.trello.loading
                visible: running
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.6
                text: {
                    if (!view.trello) return "";
                    if (view.trello.loading) return i18n("Cargando tablero…");
                    if (!view.trello.isConfigured())
                        return i18n("Configurá la API key, el token y el tablero en la pestaña «Trello» de la configuración.");
                    if (view.trello.lastError) return view.trello.lastError;
                    if (view.trello.lastFetchedAt === 0) return i18n("Pulsá ↻ para cargar el tablero.");
                    return i18n("Todas las listas están ocultas. Mostralas desde «Listas Trello» en la configuración.");
                }
            }
            Item { Layout.fillHeight: true }
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: view.trello
                      ? (Plasmoid.configuration.trelloOnlyMine !== false
                         ? i18np("%1 tarjeta mía", "%1 tarjetas mías", (view._v, view.trello.totalCount()))
                         : i18np("%1 tarjeta", "%1 tarjetas", (view._v, view.trello.totalCount())))
                      : ""
                opacity: 0.6
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            ModeMenuButton {}
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Configurar…")
                onClicked: Plasmoid.internalAction("configure").trigger()
            }
        }
    }

    TrelloCardDialog {
        id: cardDialog
        trello: view.trello
    }

    // Close the modal if the plasmoid popup is collapsed.
    Connections {
        target: view.plasmoidItem || null
        function onExpandedChanged() {
            if (!view.plasmoidItem.expanded && cardDialog.opened) cardDialog.close();
        }
    }
}
