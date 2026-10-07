import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Jira")
        icon: "go-bottom"
        source: "configJira.qml"
    }
    ConfigCategory {
        name: i18n("Clockify")
        icon: "chronometer"
        source: "configClockify.qml"
    }
    ConfigCategory {
        name: i18n("Google Calendar")
        icon: "view-calendar"
        source: "configGoogle.qml"
    }
}
