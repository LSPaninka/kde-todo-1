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
        name: i18n("Prioridades")
        icon: "flag-red"
        source: "configPriorities.qml"
    }
    ConfigCategory {
        name: i18n("Datos")
        icon: "document-save"
        source: "configData.qml"
    }
    ConfigCategory {
        name: i18n("Jira 1")
        icon: "go-bottom"
        source: "configJira.qml"
    }
    ConfigCategory {
        name: i18n("Categorías Jira 1")
        icon: "preferences-desktop-color"
        source: "configJiraCategories.qml"
    }
    ConfigCategory {
        name: i18n("Estados Jira 1")
        icon: "preferences-desktop-color"
        source: "configJiraStatuses.qml"
    }
    ConfigCategory {
        name: i18n("Jira 2")
        icon: "go-bottom"
        source: "configJira2.qml"
    }
    ConfigCategory {
        name: i18n("Categorías Jira 2")
        icon: "preferences-desktop-color"
        source: "configJira2Categories.qml"
    }
    ConfigCategory {
        name: i18n("Estados Jira 2")
        icon: "preferences-desktop-color"
        source: "configJira2Statuses.qml"
    }
    ConfigCategory {
        name: i18n("GitHub")
        icon: "applications-development"
        source: "configGh.qml"
    }
    ConfigCategory {
        name: i18n("Categorías GH")
        icon: "preferences-desktop-color"
        source: "configGhCategories.qml"
    }
    ConfigCategory {
        name: i18n("Notion")
        icon: "notes"
        source: "configNotion.qml"
    }
}
