/*
 * configGoogle.qml - Google Calendar tab.
 *
 * Read-only Google Calendar integration. Auth uses the OAuth 2.0
 * "TV and Limited Input devices" (device-code) flow, which needs no
 * redirect URI or local web server — perfect for a pure-QML plasmoid:
 *
 *   1. The user creates an OAuth client of that type in Google Cloud
 *      (free) and pastes the Client ID + Secret here.
 *   2. "Conectar con Google" requests a device code, shows a short user
 *      code and opens https://google.com/device; the user approves once.
 *   3. We poll the token endpoint until Google returns a refresh token,
 *      which we store (kcfg googleRefreshToken). The runtime store
 *      exchanges it for access tokens — Google is never written to.
 *
 * "Cargar mis calendarios" lists the account's calendars so the user can
 * pick which one to show (kcfg googleCalendarId). See docs/GOOGLE_CALENDAR.md.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property alias cfg_googleCalEnabled:    enabledCheck.checked
    property alias cfg_googleClientId:      clientIdField.text
    property alias cfg_googleClientSecret:  clientSecretField.text
    property alias cfg_googleRefreshToken:  refreshTokenField.text
    property alias cfg_googleCalDebug:      debugCheck.checked
    // Legacy single id, kept so a previously-set calendar migrates into
    // the multi-list below on first open.
    property string cfg_googleCalendarId: "primary"
    // Up-to-3 calendars, parallel lists: id + base color (hex).
    property var cfg_googleCalendarIds: []
    property var cfg_googleCalendarColors: []

    // ---- device-flow state ----
    property string _deviceCode: ""
    property int    _interval: 5
    property real   _expiresAt: 0
    property bool   _polling: false

    // ---- loaded calendar list ----
    property var _calendars: []
    property int _colorTargetRow: 0

    // Translucent-friendly palette the swatch picker offers.
    readonly property var _palette: ["#e74c3c", "#e67e22", "#f1c40f", "#2ecc71",
                                     "#1abc9c", "#3498db", "#9b59b6", "#e84393", "#95a5a6"]

    // The rows read the cfg lists DIRECTLY (not a working copy) so they
    // pick up the stored values whenever the config system loads them —
    // Component.onCompleted can run before the cfg_* arrays are injected,
    // so a snapshot there would miss them. Row 0 falls back to the legacy
    // single id for migration; the first edit writes the explicit list.
    function _idAt(i) {
        var a = cfg_googleCalendarIds || [];
        if ((!a || a.length === 0) && i === 0 &&
            cfg_googleCalendarId && ("" + cfg_googleCalendarId).trim().length > 0) {
            return ("" + cfg_googleCalendarId).trim();
        }
        return (a[i] !== undefined && a[i] !== null) ? ("" + a[i]) : "";
    }
    function _colorAt(i) {
        var c = cfg_googleCalendarColors || [];
        return (c[i] !== undefined && c[i] !== null && ("" + c[i]).length > 0)
               ? ("" + c[i]) : "#e74c3c";
    }
    // Writes keep all three slots (empties included) so id↔color stay
    // aligned by index; the store skips blank ids.
    function _setId(i, v) {
        var a = [_idAt(0), _idAt(1), _idAt(2)];
        a[i] = v || "";
        cfg_googleCalendarIds = a;
    }
    function _setColor(i, v) {
        var c = [_colorAt(0), _colorAt(1), _colorAt(2)];
        c[i] = v;
        cfg_googleCalendarColors = c;
    }

    // Options for a row's calendar combo: "(ninguno)" + loaded calendars +
    // any already-stored id that isn't in the loaded list (so it's never
    // silently dropped when the list hasn't been loaded yet).
    function _calOptions() {
        var out = [{ id: "", label: i18n("(ninguno)") }];
        var seen = {};
        for (var i = 0; i < _calendars.length; i++) { out.push(_calendars[i]); seen[_calendars[i].id] = true; }
        for (var j = 0; j < 3; j++) {
            var id = _idAt(j);
            if (id && !seen[id]) { out.push({ id: id, label: id }); seen[id] = true; }
        }
        return out;
    }
    function _optIndexOf(opts, id) {
        for (var i = 0; i < opts.length; i++) if (opts[i].id === id) return i;
        return 0;
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Integración de solo lectura con Google Calendar: muestra tus eventos como "
                 + "bloques rojos translúcidos detrás del worklog. La autorización es de una "
                 + "sola vez con un código de dispositivo (no requiere servidor local). Mirá "
                 + "docs/GOOGLE_CALENDAR.md para el paso a paso de cómo crear el cliente OAuth "
                 + "en Google Cloud (plan gratuito) y elegir el calendario.")
    }

    CheckBox {
        id: enabledCheck
        text: i18n("Mostrar los eventos de Google Calendar en el worklog")
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        TextField {
            id: clientIdField
            Kirigami.FormData.label: i18n("Client ID:")
            Layout.fillWidth: true
            placeholderText: "xxxxxxxx.apps.googleusercontent.com"
            inputMethodHints: Qt.ImhNoPredictiveText
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Client secret:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: clientSecretField
                Layout.fillWidth: true
                echoMode: showSecretCheck.checked ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            }
            CheckBox { id: showSecretCheck; text: i18n("Ver") }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Refresh token:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: refreshTokenField
                Layout.fillWidth: true
                echoMode: showTokenCheck.checked ? TextInput.Normal : TextInput.Password
                placeholderText: i18n("Se completa al autorizar")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            }
            CheckBox { id: showTokenCheck; text: i18n("Ver") }
        }
    }

    // -------- Authorize (device flow) --------
    GroupBox {
        Layout.fillWidth: true
        title: i18n("Autorizar")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: page._polling ? i18n("Esperando autorización…") : i18n("Conectar con Google")
                    icon.name: "network-connect"
                    enabled: !page._polling
                    onClicked: page._startDeviceAuth()
                }
                Button {
                    visible: page._polling
                    text: i18n("Cancelar")
                    icon.name: "dialog-cancel"
                    onClicked: page._stopPolling(i18n("Autorización cancelada."))
                }
                Item { Layout.fillWidth: true }
            }

            // The user code + open-page button, visible while authorizing.
            RowLayout {
                Layout.fillWidth: true
                visible: page._polling && userCodeLabel.text.length > 0
                Label { text: i18n("Código:"); opacity: 0.7 }
                Label {
                    id: userCodeLabel
                    text: ""
                    font.family: "monospace"
                    font.bold: true
                    font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.4)
                }
                Button {
                    text: i18n("Abrir página de Google")
                    icon.name: "internet-services"
                    onClicked: Qt.openUrlExternally(verifUrlField.text || "https://www.google.com/device")
                }
            }
            // Hidden holder for the verification URL.
            TextField { id: verifUrlField; visible: false }

            Label {
                id: authStatus
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: ""
            }
        }
    }

    // -------- Calendars (up to 3) --------
    GroupBox {
        Layout.fillWidth: true
        title: i18n("Calendarios (hasta 3)")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: i18n("Cargar mis calendarios")
                    icon.name: "view-refresh"
                    enabled: refreshTokenField.text.length > 0 &&
                             clientIdField.text.length > 0 &&
                             clientSecretField.text.length > 0
                    onClicked: page._loadCalendars()
                }
                Item { Layout.fillWidth: true }
                Label {
                    id: calStatus
                    text: ""
                    wrapMode: Text.WordWrap
                    Layout.maximumWidth: 280
                }
            }

            // Three calendar rows: pick a calendar + a (translucent) color.
            Repeater {
                model: 3
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    property int row: index

                    Label {
                        text: i18n("%1.", index + 1)
                        opacity: 0.6
                    }
                    ComboBox {
                        Layout.fillWidth: true
                        textRole: "label"
                        model: page._calOptions()
                        currentIndex: page._optIndexOf(page._calOptions(), page._idAt(row))
                        onActivated: function(idx) {
                            var opts = page._calOptions();
                            page._setId(row, opts[idx] ? opts[idx].id : "");
                        }
                    }
                    // Color swatch — opens the palette popup for this row.
                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 22
                        radius: 3
                        color: page._colorAt(row)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.4)
                        opacity: page._idAt(row).length > 0 ? 1.0 : 0.35
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { page._colorTargetRow = row; colorPopup.open(); }
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.8
                text: i18n("Elegí hasta 3 calendarios. El color por defecto es el rojo translúcido; "
                         + "podés cambiarlo por calendario (siempre se dibuja translúcido detrás del "
                         + "worklog). «primary» es tu calendario principal; para uno secundario, "
                         + "cargá la lista o usá su Calendar ID.")
            }
        }
    }

    // Shared palette popup for picking a row's color.
    Popup {
        id: colorPopup
        modal: true
        focus: true
        padding: 8
        Grid {
            columns: 5
            spacing: 6
            Repeater {
                model: page._palette
                delegate: Rectangle {
                    width: 28; height: 28
                    radius: 4
                    color: modelData
                    border.width: page._colorAt(page._colorTargetRow) === modelData ? 2 : 1
                    border.color: page._colorAt(page._colorTargetRow) === modelData
                                  ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.4)
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { page._setColor(page._colorTargetRow, modelData); colorPopup.close(); }
                    }
                }
            }
        }
    }

    CheckBox {
        id: debugCheck
        text: i18n("Loggear las llamadas a Google en plasmashell stdout")
    }

    Item { Layout.fillHeight: true }

    // Polls the token endpoint while a device authorization is pending.
    Timer {
        id: pollTimer
        interval: page._interval * 1000
        repeat: true
        onTriggered: page._pollToken()
    }

    // ------------------------------------------------------------------
    // Device flow
    // ------------------------------------------------------------------

    function _form(obj) {
        var parts = [];
        for (var k in obj) parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(obj[k]));
        return parts.join("&");
    }

    function _startDeviceAuth() {
        var id = clientIdField.text.trim();
        var secret = clientSecretField.text.trim();
        if (!id || !secret) {
            authStatus.text = i18n("Completá Client ID y Client secret primero.");
            authStatus.color = "#e74c3c";
            return;
        }
        authStatus.color = Kirigami.Theme.textColor;
        authStatus.text = i18n("Solicitando código de dispositivo…");
        userCodeLabel.text = "";

        var xhr = new XMLHttpRequest();
        xhr.open("POST", "https://oauth2.googleapis.com/device/code", true);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) {
                authStatus.text = i18n("Error solicitando código (HTTP %1): %2",
                                       xhr.status, (xhr.responseText || "").substring(0, 200));
                authStatus.color = "#e74c3c";
                return;
            }
            try {
                var d = JSON.parse(xhr.responseText);
                page._deviceCode = d.device_code || "";
                page._interval = Math.max(2, d.interval || 5);
                page._expiresAt = Date.now() + ((d.expires_in || 600) * 1000);
                userCodeLabel.text = d.user_code || "";
                verifUrlField.text = d.verification_url || d.verification_uri ||
                                     "https://www.google.com/device";
                authStatus.text = i18n("Abrí la página de Google e ingresá el código «%1». "
                                     + "Esperando tu aprobación…", d.user_code || "");
                authStatus.color = Kirigami.Theme.textColor;
                Qt.openUrlExternally(verifUrlField.text);
                page._polling = true;
                pollTimer.interval = page._interval * 1000;
                pollTimer.restart();
            } catch (e) {
                authStatus.text = i18n("Respuesta inválida del endpoint de dispositivo: %1", e);
                authStatus.color = "#e74c3c";
            }
        };
        try { xhr.send(page._form({ client_id: id,
                                    scope: "https://www.googleapis.com/auth/calendar.readonly" })); }
        catch (e) {
            authStatus.text = i18n("Error de red: %1", e);
            authStatus.color = "#e74c3c";
        }
    }

    function _pollToken() {
        if (!page._polling) { pollTimer.stop(); return; }
        if (Date.now() > page._expiresAt) {
            page._stopPolling(i18n("El código expiró. Volvé a intentar."));
            return;
        }
        var id = clientIdField.text.trim();
        var secret = clientSecretField.text.trim();
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "https://oauth2.googleapis.com/token", true);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var d = {};
            try { d = JSON.parse(xhr.responseText); } catch (e) { /* ignore */ }
            if (xhr.status === 200 && d.refresh_token) {
                refreshTokenField.text = d.refresh_token;
                page._stopPolling("");
                authStatus.text = i18n("¡Listo! Google Calendar autorizado. Cargá tus calendarios abajo.");
                authStatus.color = "#2ecc71";
                return;
            }
            // Pending / slow-down are expected; keep polling. Back off on
            // slow_down by widening the interval.
            var err = d.error || "";
            if (err === "authorization_pending") {
                return;
            } else if (err === "slow_down") {
                page._interval = page._interval + 2;
                pollTimer.interval = page._interval * 1000;
                return;
            } else if (err === "access_denied") {
                page._stopPolling(i18n("Acceso denegado en Google."));
            } else if (err === "expired_token") {
                page._stopPolling(i18n("El código expiró. Volvé a intentar."));
            } else if (xhr.status !== 200) {
                // Unknown error — surface it and stop to avoid hammering.
                page._stopPolling(i18n("Error autorizando (HTTP %1): %2",
                                       xhr.status, (err || xhr.responseText || "").substring(0, 160)));
            }
        };
        try { xhr.send(page._form({ client_id: id, client_secret: secret,
                                    device_code: page._deviceCode,
                                    grant_type: "urn:ietf:params:oauth:grant-type:device_code" })); }
        catch (e) { /* transient; next tick retries */ }
    }

    function _stopPolling(msg) {
        page._polling = false;
        pollTimer.stop();
        userCodeLabel.text = "";
        if (msg && msg.length > 0) {
            authStatus.text = msg;
            authStatus.color = "#e74c3c";
        }
    }

    // ------------------------------------------------------------------
    // Calendar list
    // ------------------------------------------------------------------

    function _loadCalendars() {
        calStatus.text = i18n("Renovando token…");
        page._accessTokenThen(function(ok, token) {
            if (!ok) {
                calStatus.text = i18n("No se pudo obtener un access token. ¿Autorizaste arriba?");
                calStatus.color = "#e74c3c";
                return;
            }
            calStatus.text = i18n("Cargando calendarios…");
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "https://www.googleapis.com/calendar/v3/users/me/calendarList", true);
            xhr.setRequestHeader("Authorization", "Bearer " + token);
            xhr.setRequestHeader("Accept", "application/json");
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status !== 200) {
                    calStatus.text = i18n("HTTP %1 al listar calendarios.", xhr.status);
                    calStatus.color = "#e74c3c";
                    return;
                }
                try {
                    var d = JSON.parse(xhr.responseText);
                    var items = d.items || [];
                    var out = [];
                    for (var i = 0; i < items.length; i++) {
                        var c = items[i];
                        out.push({
                            id: c.id,
                            label: (c.summary || c.id) + (c.primary ? i18n(" (principal)") : "")
                        });
                    }
                    page._calendars = out;
                    calStatus.text = i18np("%1 calendario encontrado.",
                                           "%1 calendarios encontrados.", out.length);
                    calStatus.color = Kirigami.Theme.textColor;
                    // The row combos rebuild from _calOptions() automatically.
                } catch (e) {
                    calStatus.text = i18n("Respuesta inválida: %1", e);
                    calStatus.color = "#e74c3c";
                }
            };
            try { xhr.send(); }
            catch (e) { calStatus.text = i18n("Error de red: %1", e); calStatus.color = "#e74c3c"; }
        });
    }

    // Exchange the refresh token for an access token (config-side, since
    // the runtime store isn't reachable from here). callback(ok, token).
    function _accessTokenThen(callback) {
        var id = clientIdField.text.trim();
        var secret = clientSecretField.text.trim();
        var refresh = refreshTokenField.text.trim();
        if (!id || !secret || !refresh) { callback(false, ""); return; }
        var xhr = new XMLHttpRequest();
        xhr.open("POST", "https://oauth2.googleapis.com/token", true);
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) { callback(false, ""); return; }
            try {
                var d = JSON.parse(xhr.responseText);
                callback(!!d.access_token, d.access_token || "");
            } catch (e) { callback(false, ""); }
        };
        try { xhr.send(page._form({ client_id: id, client_secret: secret,
                                    refresh_token: refresh, grant_type: "refresh_token" })); }
        catch (e) { callback(false, ""); }
    }
}
