/*
 * TrelloCardDialog.qml - detail / edit / create modal for a Trello card.
 *
 *   openEdit(card)    edit an existing card. Title, list, labels, members,
 *                     due date (+ completed), description are saved together
 *                     with "Guardar". Checklist items (toggle / add / delete,
 *                     new checklist) and comments apply immediately, like in
 *                     Trello itself.
 *   openNew(listId)   create a card in that list, assigned to me by default.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

QQC2.Dialog {
    id: dlg

    property var trello

    property string _cardId: ""          // "" → creating
    readonly property bool _isNew: _cardId === ""
    property var _orig: null             // card snapshot the diff is computed against
    property var _detail: null           // { card, checklists, comments } (edit mode)
    property bool _loadingDetail: false
    property bool _busy: false
    property string _error: ""
    property bool _dirty: false          // user touched a "Guardar" field
    property int _rev: 0                 // bump to refresh checklist/comment repeaters
    property string _focusChecklistId: ""

    // Working copy of the fields saved with "Guardar".
    property string _idList: ""
    property var _labelSel: []
    property var _memberSel: []

    modal: true
    anchors.centerIn: parent
    width: Math.min(620, (parent ? parent.width : 620) - 24)
    height: Math.min(660, (parent ? parent.height : 660) - 24)
    padding: 0

    onOpened: if (bodyScroll.contentItem) bodyScroll.contentItem.contentY = 0;

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.textColor
        border.width: 1
        radius: 6
    }

    // ------------------------------------------------------------------
    // Open
    // ------------------------------------------------------------------

    function openNew(listId) {
        _cardId = "";
        _orig = null;
        _detail = null;
        _error = "";
        _busy = false;
        _dirty = false;
        _idList = listId || "";
        _labelSel = [];
        _memberSel = (trello && trello.myId) ? [trello.myId] : [];
        titleField.text = "";
        descArea.text = "";
        dueField.text = "";
        dueCompleteCheck.checked = false;
        commentArea.text = "";
        open();
        titleField.forceActiveFocus();
    }

    function openEdit(card) {
        if (!card) return;
        _cardId = card.id;
        _detail = null;
        _error = "";
        _busy = false;
        _dirty = false;
        _applyCard(card);
        commentArea.text = "";
        open();
        _load();
    }

    function _applyCard(c) {
        _orig = c;
        _idList = c.idList;
        _labelSel = c.idLabels.slice();
        _memberSel = c.idMembers.slice();
        titleField.text = c.name;
        descArea.text = c.desc;
        dueField.text = _fmtDue(c.due);
        dueCompleteCheck.checked = !!c.dueComplete;
    }

    function _load() {
        if (!trello || !_cardId) return;
        _loadingDetail = true;
        var id = _cardId;
        trello.fetchCardDetail(id, function(ok, d, err) {
            if (dlg._cardId !== id) return;          // dialog moved on
            dlg._loadingDetail = false;
            if (!ok) { dlg._error = err; return; }
            dlg._detail = d;
            if (!dlg._dirty) dlg._applyCard(d.card);
            else dlg._orig = d.card;
            dlg._rev++;
        });
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _fmtDue(iso) {
        if (!iso) return "";
        var d = new Date(iso);
        return isNaN(d.getTime()) ? "" : Qt.formatDateTime(d, "dd/MM/yyyy HH:mm");
    }

    // "dd/MM/yyyy[ HH:mm]" → ISO string; "" → null; undefined if invalid.
    function _parseDue(s) {
        s = (s || "").trim();
        if (!s) return null;
        var m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$/);
        if (!m) return undefined;
        var d = new Date(+m[3], +m[2] - 1, +m[1],
                         m[4] !== undefined ? +m[4] : 12, m[5] !== undefined ? +m[5] : 0);
        if (isNaN(d.getTime()) || d.getDate() !== +m[1]) return undefined;
        return d.toISOString();
    }

    function _fmtDate(iso) {
        if (!iso) return "";
        var d = new Date(iso);
        return isNaN(d.getTime()) ? iso : Qt.formatDateTime(d, "dd/MM/yyyy hh:mm");
    }

    function _toggleIn(arr, id) {
        var out = arr.slice();
        var i = out.indexOf(id);
        if (i >= 0) out.splice(i, 1); else out.push(id);
        return out;
    }

    function _sameSet(a, b) {
        if (a.length !== b.length) return false;
        for (var i = 0; i < a.length; i++) if (b.indexOf(a[i]) < 0) return false;
        return true;
    }

    function _listNames() {
        if (!trello) return [];
        return (trello.version, trello.lists).map(function(l) { return l.name; });
    }
    function _listIndexOf(id) {
        return trello ? trello.listIndex(id) : -1;
    }

    // ------------------------------------------------------------------
    // Save (create / update)
    // ------------------------------------------------------------------

    function _save() {
        var name = titleField.text.trim();
        if (!name) { _error = i18n("El título no puede estar vacío."); return; }
        var due = _parseDue(dueField.text);
        if (due === undefined) { _error = i18n("Fecha inválida. Usá dd/MM/aaaa o dd/MM/aaaa HH:mm."); return; }
        if (!_idList) { _error = i18n("Elegí una lista."); return; }

        _busy = true;
        _error = "";

        if (_isNew) {
            trello.createCard({
                idList: _idList, name: name, desc: descArea.text,
                idLabels: _labelSel, idMembers: _memberSel, due: due
            }, function(ok, card, err) {
                dlg._busy = false;
                if (ok) dlg.close(); else dlg._error = err;
            });
            return;
        }

        var o = _orig || {};
        var f = {};
        if (name !== o.name) f.name = name;
        if (descArea.text !== o.desc) f.desc = descArea.text;
        if (_idList !== o.idList) { f.idList = _idList; f.pos = "top"; }
        if (!_sameSet(_labelSel, o.idLabels || [])) f.idLabels = _labelSel;
        if (!_sameSet(_memberSel, o.idMembers || [])) f.idMembers = _memberSel;
        var origDue = o.due ? new Date(o.due).toISOString() : null;
        if (due !== origDue) f.due = due;
        if (due && dueCompleteCheck.checked !== !!o.dueComplete) f.dueComplete = dueCompleteCheck.checked;

        if (Object.keys(f).length === 0) { _busy = false; close(); return; }
        trello.updateCard(_cardId, f, function(ok, card, err) {
            dlg._busy = false;
            if (ok) dlg.close(); else dlg._error = err;
        });
    }

    // ------------------------------------------------------------------
    // Checklists (immediate)
    // ------------------------------------------------------------------

    function _findChecklist(id) {
        var cls = _detail ? _detail.checklists : [];
        for (var i = 0; i < cls.length; i++) if (cls[i].id === id) return cls[i];
        return null;
    }
    function _afterChecklistChange() {
        _rev++;
        if (trello && _detail) trello.syncChecklistBadges(_cardId, _detail.checklists);
    }

    // Look items up by id: a Repeater's modelData over a JS array may be a
    // converted copy, so mutating it would not reach _detail.
    function _findItem(checklistId, itemId) {
        var cl = _findChecklist(checklistId);
        if (!cl) return null;
        for (var i = 0; i < cl.items.length; i++) if (cl.items[i].id === itemId) return cl.items[i];
        return null;
    }

    function _toggleItem(checklistId, itemId, complete) {
        var item = _findItem(checklistId, itemId);
        if (!item) return;
        var prev = item.state;
        item.state = complete ? "complete" : "incomplete";
        _afterChecklistChange();
        trello.setCheckItemState(_cardId, itemId, complete, function(ok, d, err) {
            if (!ok) {
                var it = dlg._findItem(checklistId, itemId);
                if (it) it.state = prev;
                dlg._error = err;
                dlg._afterChecklistChange();
            }
        });
    }

    function _addItem(checklistId, name) {
        name = (name || "").trim();
        if (!name) return;
        trello.addCheckItem(checklistId, name, function(ok, it, err) {
            if (!ok) { dlg._error = err; return; }
            var cl = dlg._findChecklist(checklistId);
            if (cl) cl.items.push({ id: it.id, name: it.name || name, state: it.state || "incomplete", pos: it.pos || 0 });
            dlg._focusChecklistId = checklistId;
            dlg._afterChecklistChange();
        });
    }

    function _deleteItem(checklistId, itemId) {
        trello.deleteCheckItem(checklistId, itemId, function(ok, d, err) {
            if (!ok) { dlg._error = err; return; }
            var cl = dlg._findChecklist(checklistId);
            if (cl) cl.items = cl.items.filter(function(x) { return x.id !== itemId; });
            dlg._afterChecklistChange();
        });
    }

    function _newChecklist(name) {
        trello.createChecklist(_cardId, (name || "").trim() || "Checklist", function(ok, cl, err) {
            if (!ok) { dlg._error = err; return; }
            if (dlg._detail) dlg._detail.checklists.push({ id: cl.id, name: cl.name || "Checklist", pos: cl.pos || 0, items: [] });
            dlg._focusChecklistId = cl.id;
            newChecklistField.text = "";
            dlg._afterChecklistChange();
        });
    }

    function _comment() {
        var t = commentArea.text.trim();
        if (!t || !trello) return;
        _busy = true;
        trello.addComment(_cardId, t, function(ok, a, err) {
            dlg._busy = false;
            if (!ok) { dlg._error = err; return; }
            commentArea.text = "";
            var me = trello.memberById(trello.myId);
            var mc = (a && a.memberCreator) || {};
            if (dlg._detail) dlg._detail.comments.unshift({
                id: a ? a.id : "",
                author: mc.fullName || (me ? me.fullName : i18n("Yo")),
                initials: mc.initials || (me ? me.initials : "?"),
                authorId: trello.myId,
                date: (a && a.date) || new Date().toISOString(),
                text: t
            });
            dlg._rev++;
        });
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------

    // Plain Item wrapper: a Layout used directly as contentItem collapses to
    // its implicit height on reopen (QQC2.Dialog quirk).
    contentItem: Item {
      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // -------- Header: title + close --------
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: dlg._isNew ? "document-new" : "view-list-details"
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
            }
            PlasmaComponents3.TextField {
                id: titleField
                Layout.fillWidth: true
                font.bold: true
                placeholderText: i18n("Título de la tarjeta")
                onTextEdited: dlg._dirty = true
                onAccepted: dlg._save()
            }
            PlasmaComponents3.ToolButton {
                icon.name: "window-close"
                onClicked: dlg.close()
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(1, 1, 1, 0.12) }

        // -------- Scrollable body --------
        QQC2.ScrollView {
            id: bodyScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: bodyScroll.availableWidth
                spacing: Kirigami.Units.smallSpacing

                GridLayout {
                    Layout.fillWidth: true
                    Layout.margins: Kirigami.Units.smallSpacing * 2
                    columns: 2
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing

                    // List (moving a card = changing its list).
                    PlasmaComponents3.Label { text: i18n("Lista:"); opacity: 0.7 }
                    PlasmaComponents3.ComboBox {
                        Layout.fillWidth: true
                        model: dlg._listNames()
                        currentIndex: dlg._listIndexOf(dlg._idList)
                        onActivated: (i) => {
                            if (dlg.trello && dlg.trello.lists[i]) {
                                dlg._idList = dlg.trello.lists[i].id;
                                dlg._dirty = true;
                            }
                        }
                    }

                    // Due date.
                    PlasmaComponents3.Label { text: i18n("Vencimiento:"); opacity: 0.7 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.TextField {
                            id: dueField
                            Layout.preferredWidth: 150
                            placeholderText: "dd/MM/aaaa HH:mm"
                            inputMethodHints: Qt.ImhDigitsOnly
                            onTextEdited: dlg._dirty = true
                        }
                        PlasmaComponents3.ToolButton {
                            icon.name: "go-jump-today"
                            onClicked: {
                                var d = new Date();
                                d.setHours(18, 0, 0, 0);
                                dueField.text = Qt.formatDateTime(d, "dd/MM/yyyy HH:mm");
                                dlg._dirty = true;
                            }
                            PlasmaComponents3.ToolTip.text: i18n("Hoy 18:00")
                            PlasmaComponents3.ToolTip.visible: hovered
                            PlasmaComponents3.ToolTip.delay: 500
                        }
                        PlasmaComponents3.ToolButton {
                            icon.name: "edit-clear"
                            enabled: dueField.text.length > 0
                            onClicked: { dueField.text = ""; dueCompleteCheck.checked = false; dlg._dirty = true; }
                            PlasmaComponents3.ToolTip.text: i18n("Quitar vencimiento")
                            PlasmaComponents3.ToolTip.visible: hovered
                            PlasmaComponents3.ToolTip.delay: 500
                        }
                        PlasmaComponents3.CheckBox {
                            id: dueCompleteCheck
                            text: i18n("Completada")
                            enabled: dueField.text.trim().length > 0
                            onToggled: dlg._dirty = true
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // -------- Labels --------
                PlasmaComponents3.Label {
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    text: i18n("Etiquetas"); opacity: 0.7; font.bold: true
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                    spacing: 6

                    Repeater {
                        model: dlg.trello ? (dlg.trello.version, dlg.trello.labels) : []
                        delegate: Rectangle {
                            property bool sel: dlg._labelSel.indexOf(modelData.id) >= 0
                            property color bg: dlg.trello.labelColor(modelData.color)
                            width: chipRow.implicitWidth + 14
                            height: 24
                            radius: 4
                            color: bg
                            opacity: sel ? 1.0 : 0.35
                            border.width: sel ? 2 : 0
                            border.color: Kirigami.Theme.highlightColor
                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 4
                                Kirigami.Icon {
                                    visible: parent.parent.sel
                                    source: "checkmark"
                                    Layout.preferredWidth: 12
                                    Layout.preferredHeight: 12
                                }
                                PlasmaComponents3.Label {
                                    text: modelData.name || modelData.color || i18n("(sin nombre)")
                                    color: dlg.trello.contrastText(parent.parent.bg.toString())
                                    font.bold: true
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { dlg._labelSel = dlg._toggleIn(dlg._labelSel, modelData.id); dlg._dirty = true; }
                            }
                        }
                    }
                }

                // -------- Members --------
                PlasmaComponents3.Label {
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: i18n("Miembros"); opacity: 0.7; font.bold: true
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                    spacing: 6

                    Repeater {
                        model: dlg.trello ? (dlg.trello.version, dlg.trello.members) : []
                        delegate: Rectangle {
                            property bool sel: dlg._memberSel.indexOf(modelData.id) >= 0
                            width: memRow.implicitWidth + 12
                            height: 28
                            radius: 14
                            color: sel ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                            border.width: 1
                            border.color: sel ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.15)
                            opacity: sel ? 1.0 : 0.6
                            RowLayout {
                                id: memRow
                                anchors.centerIn: parent
                                spacing: 6
                                Rectangle {
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    radius: 11
                                    color: dlg.trello.memberColor(modelData.id)
                                    PlasmaComponents3.Label {
                                        anchors.centerIn: parent
                                        text: modelData.initials
                                        color: "white"
                                        font.bold: true
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize - 1
                                    }
                                }
                                PlasmaComponents3.Label {
                                    text: modelData.fullName + (dlg.trello && modelData.id === dlg.trello.myId ? i18n(" (yo)") : "")
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize + 1
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { dlg._memberSel = dlg._toggleIn(dlg._memberSel, modelData.id); dlg._dirty = true; }
                            }
                        }
                    }
                }

                // -------- Description --------
                PlasmaComponents3.Label {
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: i18n("Descripción"); opacity: 0.7; font.bold: true
                }
                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                    Layout.preferredHeight: 120
                    PlasmaComponents3.TextArea {
                        id: descArea
                        wrapMode: TextEdit.Wrap
                        placeholderText: i18n("Agregá una descripción más detallada…")
                        onTextChanged: if (activeFocus) dlg._dirty = true
                    }
                }

                // -------- Checklists (edit mode) --------
                RowLayout {
                    visible: !dlg._isNew
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        text: i18n("Checklists"); opacity: 0.7; font.bold: true
                        Layout.fillWidth: true
                    }
                    PlasmaComponents3.BusyIndicator {
                        running: dlg._loadingDetail
                        visible: running
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                    }
                }

                Repeater {
                    model: (dlg._rev, dlg._detail ? dlg._detail.checklists.slice() : [])
                    delegate: ColumnLayout {
                        id: clCol
                        property var cl: modelData
                        property int doneCount: cl.items.filter(function(x) { return x.state === "complete"; }).length
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                        Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Kirigami.Icon { source: "checkbox"; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                            PlasmaComponents3.Label {
                                text: clCol.cl.name
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            PlasmaComponents3.Label {
                                text: clCol.doneCount + "/" + clCol.cl.items.length
                                opacity: 0.7
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                        }
                        Rectangle {
                            id: clTrack
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.10)
                            Rectangle {
                                width: clCol.cl.items.length > 0 ? Math.round(clTrack.width * clCol.doneCount / clCol.cl.items.length) : 0
                                height: parent.height
                                radius: 2
                                color: clCol.doneCount === clCol.cl.items.length ? "#4bce97" : "#579dff"
                            }
                        }

                        Repeater {
                            model: clCol.cl.items.slice()
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents3.CheckBox {
                                    checked: modelData.state === "complete"
                                    onToggled: dlg._toggleItem(clCol.cl.id, modelData.id, checked)
                                }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    wrapMode: Text.WordWrap
                                    font.strikeout: modelData.state === "complete"
                                    opacity: modelData.state === "complete" ? 0.6 : 1.0
                                }
                                PlasmaComponents3.ToolButton {
                                    icon.name: "edit-delete"
                                    onClicked: dlg._deleteItem(clCol.cl.id, modelData.id)
                                    PlasmaComponents3.ToolTip.text: i18n("Borrar ítem")
                                    PlasmaComponents3.ToolTip.visible: hovered
                                    PlasmaComponents3.ToolTip.delay: 500
                                }
                            }
                        }

                        PlasmaComponents3.TextField {
                            id: addItemField
                            Layout.fillWidth: true
                            placeholderText: i18n("Agregar un ítem… (Enter)")
                            onAccepted: { dlg._addItem(clCol.cl.id, text); text = ""; }
                            Component.onCompleted: {
                                if (dlg._focusChecklistId === clCol.cl.id) {
                                    dlg._focusChecklistId = "";
                                    forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    visible: !dlg._isNew && dlg._detail !== null
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                    PlasmaComponents3.TextField {
                        id: newChecklistField
                        Layout.fillWidth: true
                        placeholderText: i18n("Nombre de la nueva checklist")
                        onAccepted: dlg._newChecklist(text)
                    }
                    PlasmaComponents3.Button {
                        icon.name: "list-add"
                        text: i18n("Nueva checklist")
                        onClicked: dlg._newChecklist(newChecklistField.text)
                    }
                }

                // -------- Comments (edit mode) --------
                PlasmaComponents3.Label {
                    visible: !dlg._isNew
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.topMargin: Kirigami.Units.smallSpacing * 2
                    text: (dlg._rev, dlg._detail)
                          ? i18np("Comentario (%1)", "Comentarios (%1)", dlg._detail.comments.length)
                          : i18n("Comentarios")
                    opacity: 0.7
                    font.bold: true
                }
                RowLayout {
                    visible: !dlg._isNew
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        PlasmaComponents3.TextArea {
                            id: commentArea
                            wrapMode: TextEdit.Wrap
                            placeholderText: i18n("Escribí un comentario…")
                        }
                    }
                    PlasmaComponents3.Button {
                        icon.name: "mail-send"
                        text: i18n("Comentar")
                        enabled: !dlg._busy && commentArea.text.trim().length > 0
                        onClicked: dlg._comment()
                    }
                }

                Repeater {
                    model: (dlg._rev, dlg._detail ? dlg._detail.comments.slice() : [])
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                        Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                        radius: 4
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        implicitHeight: cmtCol.implicitHeight + 12
                        ColumnLayout {
                            id: cmtCol
                            x: 8; y: 6
                            width: parent.width - 16
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 10
                                    color: dlg.trello ? dlg.trello.memberColor(modelData.authorId) : "#0079bf"
                                    PlasmaComponents3.Label {
                                        anchors.centerIn: parent
                                        text: modelData.initials
                                        color: "white"
                                        font.bold: true
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize - 2
                                    }
                                }
                                PlasmaComponents3.Label {
                                    text: modelData.author
                                    font.bold: true
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize + 1
                                }
                                Item { Layout.fillWidth: true }
                                PlasmaComponents3.Label {
                                    text: dlg._fmtDate(modelData.date)
                                    opacity: 0.55
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                }
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: modelData.text
                                wrapMode: Text.WordWrap
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize + 1
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.rgba(1, 1, 1, 0.12) }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: dlg._error || (dlg._busy ? i18n("Guardando…") : "")
                color: dlg._error ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                wrapMode: Text.WordWrap
                opacity: dlg._error ? 1.0 : 0.7
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
            PlasmaComponents3.ToolButton {
                visible: !dlg._isNew
                icon.name: "globe"
                enabled: dlg._orig && dlg._orig.url
                onClicked: Qt.openUrlExternally(dlg._orig.url)
                PlasmaComponents3.ToolTip.text: i18n("Abrir en Trello")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.Button {
                text: i18n("Cancelar")
                onClicked: dlg.close()
            }
            PlasmaComponents3.Button {
                icon.name: dlg._isNew ? "list-add" : "document-save"
                text: dlg._isNew ? i18n("Crear") : i18n("Guardar")
                enabled: !dlg._busy && titleField.text.trim().length > 0
                onClicked: dlg._save()
            }
        }
      }
    }
}
