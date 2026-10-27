/*
 * configTrello.qml - "Trello" tab of the configuration dialog.
 *
 *   - API key (https://trello.com/power-ups/admin → your Power-Up → API key)
 *   - Token: "Generar token" opens Trello's authorize page for that key
 *     (scope read,write, no expiration); paste the token it shows.
 *   - Board: paste its URL, or "Cargar mis tableros" and pick one.
 *   - "Solo mis tarjetas", auto-refresh, debug logs, connection test.
 *
 * The buttons use the values currently typed in the form (not yet applied).
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Plasma 6 also assigns cfg_<key>Default; declare them to avoid warnings.
    property var cfg_trelloApiKeyDefault
    property var cfg_trelloTokenDefault
    property var cfg_trelloBoardDefault
    property var cfg_trelloOnlyMineDefault
    property var cfg_trelloRefreshMinutesDefault
    property var cfg_trelloDebugDefault

    property alias cfg_trelloApiKey:         keyField.text
    property alias cfg_trelloToken:          tokenField.text
    property alias cfg_trelloBoard:          boardField.text
    property alias cfg_trelloOnlyMine:       onlyMineCheck.checked
    property alias cfg_trelloRefreshMinutes: refreshSpin.value
    property alias cfg_trelloDebug:          debugCheck.checked

    property var _boards: []

    function _authHeader() {
        return 'OAuth oauth_consumer_key="' + keyField.text.trim() +
               '", oauth_token="' + tokenField.text.trim() + '"';
    }

    function _get(path, cb) {
        if (!keyField.text.trim() || !tokenField.text.trim()) {
            cb(false, null, i18n("Completá la API key y el token primero."));
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.trello.com/1" + path, true);
        xhr.setRequestHeader("Authorization", page._authHeader());
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try { cb(true, JSON.parse(xhr.responseText), ""); }
                catch (e) { cb(false, null, i18n("Respuesta inválida: %1", e)); }
            } else if (xhr.status === 401) {
                cb(false, null, i18n("Key/token rechazados (HTTP 401)."));
            } else if (xhr.status === 0) {
                cb(false, null, i18n("No se pudo contactar api.trello.com."));
            } else {
                cb(false, null, i18n("HTTP %1: %2", xhr.status, (xhr.responseText || "").substring(0, 200)));
            }
        };
        try { xhr.send(); } catch (e) { cb(false, null, i18n("Error de red: %1", e)); }
    }

    function _setStatus(ok, msg) {
        statusLabel.text = msg;
        statusLabel.color = ok ? "#2ecc71" : "#e74c3c";
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true

            RowLayout {
                Kirigami.FormData.label: i18n("API key:")
                spacing: Kirigami.Units.smallSpacing
                TextField {
                    id: keyField
                    Layout.fillWidth: true
                    placeholderText: i18n("32 caracteres hexadecimales")
                    inputMethodHints: Qt.ImhNoPredictiveText
                }
                Button {
                    text: i18n("Obtener…")
                    icon.name: "globe"
                    onClicked: Qt.openUrlExternally("https://trello.com/power-ups/admin")
                    ToolTip.text: i18n("Abre el portal de Power-Ups: creá uno y copiá su API key")
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                }
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Token:")
                spacing: Kirigami.Units.smallSpacing
                TextField {
                    id: tokenField
                    Layout.fillWidth: true
                    echoMode: showTokenCheck.checked ? TextInput.Normal : TextInput.Password
                    placeholderText: i18n("ATTA…")
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                }
                CheckBox {
                    id: showTokenCheck
                    text: i18n("Ver")
                }
                Button {
                    text: i18n("Generar token…")
                    icon.name: "dialog-password"
                    enabled: keyField.text.trim().length > 0
                    onClicked: Qt.openUrlExternally(
                        "https://trello.com/1/authorize?expiration=never&scope=read,write" +
                        "&response_type=token&name=" + encodeURIComponent("Categorized ToDo (KDE)") +
                        "&key=" + encodeURIComponent(keyField.text.trim()))
                    ToolTip.text: i18n("Autorizá el acceso (lectura y escritura) y pegá acá el token que te muestra Trello")
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                }
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Tablero:")
                spacing: Kirigami.Units.smallSpacing
                TextField {
                    id: boardField
                    Layout.fillWidth: true
                    placeholderText: "https://trello.com/b/AbCd1234/mi-tablero"
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
                }
                Button {
                    text: i18n("Cargar mis tableros")
                    icon.name: "view-refresh"
                    onClicked: {
                        page._setStatus(true, i18n("Cargando tableros…"));
                        page._get("/members/me/boards?filter=open&fields=name,shortUrl,url", function(ok, data, err) {
                            if (!ok) { page._setStatus(false, err); return; }
                            page._boards = data || [];
                            page._setStatus(true, i18np("%1 tablero encontrado. Elegilo abajo.",
                                                        "%1 tableros encontrados. Elegí uno abajo.",
                                                        page._boards.length));
                        });
                    }
                }
            }

            ComboBox {
                Kirigami.FormData.label: i18n("Mis tableros:")
                visible: page._boards.length > 0
                Layout.fillWidth: true
                model: page._boards.map(function(b) { return b.name; })
                currentIndex: -1
                displayText: currentIndex < 0 ? i18n("Elegí un tablero…") : currentText
                onActivated: (i) => {
                    var b = page._boards[i];
                    if (b) boardField.text = b.shortUrl || b.url;
                }
            }

            CheckBox {
                id: onlyMineCheck
                Kirigami.FormData.label: i18n("Filtro:")
                text: i18n("Solo tarjetas asignadas a mí")
            }

            SpinBox {
                id: refreshSpin
                Kirigami.FormData.label: i18n("Auto-refresh (min):")
                from: 0
                to: 1440
                stepSize: 1
            }

            CheckBox {
                id: debugCheck
                Kirigami.FormData.label: i18n("Logs de depuración:")
                text: i18n("Loggear fetch/escrituras en plasmashell stdout")
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
                            page._setStatus(true, i18n("Conectando…"));
                            page._get("/members/me?fields=fullName,username", function(ok, d, err) {
                                if (ok) page._setStatus(true, i18n("OK — autenticado como %1", d.fullName || d.username || "?"));
                                else page._setStatus(false, err);
                            });
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
                "1) En https://trello.com/power-ups/admin creá un Power-Up (cualquier nombre) y "
              + "copiá su «API key». 2) Pulsá «Generar token…», autorizá y pegá el token. "
              + "3) Pegá la URL del tablero o elegilo con «Cargar mis tableros». "
              + "Las listas se ocultan y colorean en la pestaña «Listas Trello». "
              + "Key y token se guardan en texto plano en ~/.config/plasma-org.kde.plasma.desktop-appletsrc.")
        }

        Item { Layout.fillHeight: true }
    }
}
