import QtQuick 2.15
import org.kde.plasma.configuration 2.0

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
}
