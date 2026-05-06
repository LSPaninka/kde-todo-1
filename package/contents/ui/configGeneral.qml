/*
 * configGeneral.qml - General tab of the plasmoid configuration dialog.
 *
 * KCM-style form: every `cfg_<name>` property gets auto-saved/loaded into
 * the matching kcfg entry declared in config/main.xml.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

Kirigami.FormLayout {
    id: page

    // Bindings to main.xml entries.
    property string cfg_mode: "todo"
    property alias cfg_categoryCount: catCountSpin.value
    property alias cfg_showPriorityIcons: showPrioCheck.checked
    property alias cfg_confirmDelete: confirmDeleteCheck.checked
    property alias cfg_popupWidth: popupW.value
    property alias cfg_popupHeight: popupH.value

    ButtonGroup { id: modeGroup }

    RowLayout {
        Kirigami.FormData.label: i18n("Modo:")
        spacing: Kirigami.Units.smallSpacing

        RadioButton {
            ButtonGroup.group: modeGroup
            text: i18n("ToDo")
            checked: page.cfg_mode === "todo"
            onToggled: if (checked) page.cfg_mode = "todo"
        }
        RadioButton {
            ButtonGroup.group: modeGroup
            text: i18n("Jira")
            checked: page.cfg_mode === "jira"
            onToggled: if (checked) page.cfg_mode = "jira"
        }
    }

    Label {
        Layout.preferredWidth: 360
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.65
        text: i18n("ToDo: lista de tareas local con categorías, prioridades y archivado. "
                 + "Jira: muestra (sólo lectura) las incidencias asignadas a vos en Jira "
                 + "Cloud. La pestaña «Jira» configura las credenciales.")
    }

    Item { Kirigami.FormData.isSection: true }

    // -------- ToDo-specific section --------
    SpinBox {
        id: catCountSpin
        Kirigami.FormData.label: i18n("Número de categorías:")
        from: 1
        to: 4
        stepSize: 1
    }

    CheckBox {
        id: showPrioCheck
        Kirigami.FormData.label: i18n("Prioridades:")
        text: i18n("Mostrar insignias de prioridad (XS/S/M/L/XL)")
    }

    CheckBox {
        id: confirmDeleteCheck
        Kirigami.FormData.label: i18n("Borrado:")
        text: i18n("Confirmar antes de borrar permanentemente archivadas")
    }

    Item { Kirigami.FormData.isSection: true }

    SpinBox {
        id: popupW
        Kirigami.FormData.label: i18n("Ancho del popup (px):")
        from: 280
        to: 900
        stepSize: 10
    }

    SpinBox {
        id: popupH
        Kirigami.FormData.label: i18n("Alto del popup (px):")
        from: 300
        to: 1200
        stepSize: 10
    }
}
