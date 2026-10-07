import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

// Simula el panel (44 px) con la CompactRepresentation y el popup con la
// FullRepresentation del main.qml real.
Rectangle {
    id: host
    width: 980
    height: 760
    color: "#1b1e20"

    property var app: null
    property Item compactItem: null
    property Item fullItem: null

    Rectangle {
        id: panelBg
        x: 10; y: 10
        width: 520; height: 44
        color: "#2a2e32"
        RowLayout {
            id: panel
            anchors.fill: parent
            spacing: 0
            Item { Layout.fillWidth: true }
        }
    }
    Text {
        x: 540; y: 14
        color: "#fcfcfc"
        text: host.app ? ("tooltip: " + host.app.toolTipMainText + " | " + host.app.toolTipSubText) : ""
    }
    Rectangle {
        id: popupBg
        x: 10; y: 64
        width: 960; height: 690
        color: "#2a2e32"
        border.color: "#4d5258"
        Item { id: popupHost; anchors.fill: parent }
    }

    function start(mainUrl) {
        var c = Qt.createComponent(mainUrl);
        if (c.status !== Component.Ready) {
            console.warn("HARNESS: no se pudo cargar main.qml: " + c.errorString());
            return;
        }
        app = c.createObject(host);
        compactItem = app.compactRepresentation.createObject(panel);
        fullItem = app.fullRepresentation.createObject(popupHost);
        fullItem.anchors.fill = popupHost;
        fullItem.width = Qt.binding(function() { return popupHost.width; });
        fullItem.height = Qt.binding(function() { return popupHost.height; });
    }

    function setMode(m) { Plasmoid.configuration.mode = m; }
    function cfg(k, v) { Plasmoid.configuration[k] = v; }
    function cfg_get(k) { return Plasmoid.configuration[k]; }
    function store() { return compactItem.store; }
    function jira() { return compactItem.jira; }
    function jira2() { return compactItem.jira2; }

    // Carga una página de configuración en el área del popup. Devuelve "" si
    // todo fue bien o el texto del error.
    property Item page: null
    function loadPage(url) {
        if (page) { page.visible = false; page.destroy(); page = null; }
        if (fullItem) fullItem.visible = false;
        var c = Qt.createComponent(url);
        if (c.status !== Component.Ready) return c.errorString();
        page = c.createObject(popupHost);
        if (!page) return "createObject devolvió null";
        page.width = Qt.binding(function() { return popupHost.width; });
        return "";
    }
}
