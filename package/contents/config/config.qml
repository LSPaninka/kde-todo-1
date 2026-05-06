import QtQuick 2.15
import org.kde.plasma.configuration 2.0

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Categories")
        icon: "preferences-desktop-color"
        source: "configCategories.qml"
    }
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-theme"
        source: "configAppearance.qml"
    }
    ConfigCategory {
        name: i18n("Jira")
        icon: "go-bottom"
        source: "configJira.qml"
    }
    ConfigCategory {
        name: i18n("Categorías Jira")
        icon: "preferences-desktop-color"
        source: "configJiraCategories.qml"
    }
}
