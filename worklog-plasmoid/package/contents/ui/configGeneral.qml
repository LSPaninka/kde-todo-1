/*
 * configGeneral.qml - General tab.
 * Bindings to KCfg entries via the cfg_* alias / property pattern.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_worklogViewMode: "9h"
    property alias  cfg_worklogPopupWidth:        popupW.value
    property alias  cfg_worklogPopupHeight:       popupH.value
    property alias  cfg_worklogModalWidth:        modalW.value
    property alias  cfg_worklogModalHeight:       modalH.value
    property alias  cfg_worklogDailyTargetHours:  targetSpin.value
    property alias  cfg_worklogIssueJql:          jqlField.text
    property alias  cfg_worklogIssueMax:          maxSpin.value
    property alias  cfg_worklogShowIssueSummary:  showSummaryCheck.checked
    property alias  cfg_worklogShowSprintGauges:  sprintGaugesCheck.checked
    property alias  cfg_worklogShowSubtaskTable:  subtaskTableCheck.checked
    property alias  cfg_worklogSubtaskJql:        subtaskJqlField.text
    property alias  cfg_worklogSubtaskShowParent: subtaskShowParentCheck.checked
    property string cfg_worklogSprintStrategy:    "subtask-customfield"
    property alias  cfg_worklogSprintField:       sprintFieldField.text
    property alias  cfg_worklogSprintBoardId:     sprintBoardIdSpin.value
    property string cfg_worklogRemainingMode:     "api"
    property alias  cfg_worklogDebug:             debugCheck.checked

    ButtonGroup { id: viewGroup }

    RowLayout {
        Kirigami.FormData.label: i18n("Modo de vista:")
        spacing: Kirigami.Units.smallSpacing

        RadioButton {
            ButtonGroup.group: viewGroup
            text: i18n("9h (09:00 – 18:00)")
            checked: page.cfg_worklogViewMode === "9h"
            onToggled: if (checked) page.cfg_worklogViewMode = "9h"
        }
        RadioButton {
            ButtonGroup.group: viewGroup
            text: i18n("24h (00:00 – 24:00)")
            checked: page.cfg_worklogViewMode === "24h"
            onToggled: if (checked) page.cfg_worklogViewMode = "24h"
        }
    }

    Item { Kirigami.FormData.isSection: true }

    SpinBox {
        id: popupW
        Kirigami.FormData.label: i18n("Ancho del popup (px):")
        from: 600
        to: 2200
        stepSize: 20
    }
    SpinBox {
        id: popupH
        Kirigami.FormData.label: i18n("Alto del popup (px):")
        from: 400
        to: 1500
        stepSize: 20
    }

    SpinBox {
        id: modalW
        Kirigami.FormData.label: i18n("Ancho del modal (px):")
        from: 420
        to: 1600
        stepSize: 20
    }
    SpinBox {
        id: modalH
        Kirigami.FormData.label: i18n("Alto del modal (px):")
        from: 360
        to: 1200
        stepSize: 20
    }

    Item { Kirigami.FormData.isSection: true }

    SpinBox {
        id: targetSpin
        Kirigami.FormData.label: i18n("Objetivo diario (h):")
        from: 0
        to: 24
        stepSize: 1
    }

    TextField {
        id: jqlField
        Kirigami.FormData.label: i18n("JQL del picker:")
        Layout.fillWidth: true
        placeholderText: "assignee = currentUser() AND statusCategory != Done"
    }

    SpinBox {
        id: maxSpin
        Kirigami.FormData.label: i18n("Máx. issues en el picker:")
        from: 10
        to: 200
        stepSize: 10
    }

    CheckBox {
        id: showSummaryCheck
        Kirigami.FormData.label: i18n("Bloques:")
        text: i18n("Mostrar también el título de la issue (el código siempre se muestra)")
    }

    CheckBox {
        id: sprintGaugesCheck
        Kirigami.FormData.label: i18n("Panel inferior:")
        text: i18n("Mostrar el panel debajo del calendario (anillos Sprint/Horas, tabla de " +
                   "subtareas o heatmap mensual; se alternan con el switch vertical a la " +
                   "derecha del panel)")
    }

    CheckBox {
        id: subtaskTableCheck
        Kirigami.FormData.label: i18n("Tabla de subtareas:")
        text: i18n("Habilitar la tercera sección del panel inferior (tabla de subtareas)")
    }

    TextField {
        id: subtaskJqlField
        Kirigami.FormData.label: i18n("JQL de subtareas:")
        Layout.fillWidth: true
        placeholderText: "issuetype in subTaskIssueTypes() AND assignee = currentUser() AND statusCategory != Done"
        enabled: subtaskTableCheck.checked
    }

    CheckBox {
        id: subtaskShowParentCheck
        Kirigami.FormData.label: i18n("Columna padre:")
        text: i18n("Mostrar la issue madre de cada subtarea (con tooltip del título)")
        enabled: subtaskTableCheck.checked
    }

    CheckBox {
        id: debugCheck
        Kirigami.FormData.label: i18n("Logs:")
        text: i18n("Loggear fetch/parse en plasmashell stdout")
    }

    Item { Kirigami.FormData.isSection: true }

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 400
        wrapMode: Text.WordWrap
        opacity: 0.65
        text: i18n("Sprint (experimental) — cómo descubre el plasmoide cuál es tu sprint "
                 + "activo de Jira. La opción «Subtarea + customfield» funciona incluso si "
                 + "solo tenés subtareas asignadas (las historias padre quedan sin asignar). "
                 + "«Board ID» va directo al endpoint de agile y necesita el id del board. "
                 + "«Assignee JQL» es la query original de 0.4.0, útil si tu cuenta tiene "
                 + "issues asignadas a vos directamente.")
    }

    ButtonGroup { id: sprintStrategyGroup }

    RadioButton {
        Kirigami.FormData.label: i18n("Estrategia:")
        ButtonGroup.group: sprintStrategyGroup
        text: i18n("Subtarea + customfield")
        checked: page.cfg_worklogSprintStrategy === "subtask-customfield"
        onToggled: if (checked) page.cfg_worklogSprintStrategy = "subtask-customfield"
    }
    RadioButton {
        ButtonGroup.group: sprintStrategyGroup
        text: i18n("Board ID (agile)")
        checked: page.cfg_worklogSprintStrategy === "agile-board"
        onToggled: if (checked) page.cfg_worklogSprintStrategy = "agile-board"
    }
    RadioButton {
        ButtonGroup.group: sprintStrategyGroup
        text: i18n("Assignee JQL (legacy 0.4.0)")
        checked: page.cfg_worklogSprintStrategy === "assignee-jql"
        onToggled: if (checked) page.cfg_worklogSprintStrategy = "assignee-jql"
    }

    TextField {
        id: sprintFieldField
        Kirigami.FormData.label: i18n("Custom field:")
        Layout.fillWidth: true
        placeholderText: "customfield_10020"
        enabled: page.cfg_worklogSprintStrategy !== "agile-board"
    }

    SpinBox {
        id: sprintBoardIdSpin
        Kirigami.FormData.label: i18n("Board ID:")
        from: 0
        to: 9999999
        stepSize: 1
        enabled: page.cfg_worklogSprintStrategy === "agile-board"
    }

    Item { Kirigami.FormData.isSection: true }

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 400
        wrapMode: Text.WordWrap
        opacity: 0.65
        text: i18n("Horas restantes — cómo calcular las horas «Disponibles» del anillo y "
                 + "la columna derecha del picker. «API» usa el remainingEstimate de Jira. "
                 + "«Calculado» usa originalEstimate − timeSpent, útil cuando "
                 + "remainingEstimate no se va actualizando al cargar horas.")
    }

    ButtonGroup { id: remainingModeGroup }
    RadioButton {
        Kirigami.FormData.label: i18n("Remaining:")
        ButtonGroup.group: remainingModeGroup
        text: i18n("API (remainingEstimate)")
        checked: page.cfg_worklogRemainingMode === "api"
        onToggled: if (checked) page.cfg_worklogRemainingMode = "api"
    }
    RadioButton {
        ButtonGroup.group: remainingModeGroup
        text: i18n("Calculado (original − spent)")
        checked: page.cfg_worklogRemainingMode === "calculated"
        onToggled: if (checked) page.cfg_worklogRemainingMode = "calculated"
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 400
        wrapMode: Text.WordWrap
        opacity: 0.65
        text: i18n("Las credenciales de Jira (sitio, email, token) se editan en la pestaña «Jira». "
                 + "Están compartidas con el plasmoide Categorized ToDo, así que si ya tenés ese "
                 + "instalado y configurado, este plasmoide ya las ve.")
    }
}
