import QtQuick

// Simulación mínima: el contenido llena el ancho de la página (como
// Kirigami.ScrollablePage hace con su único hijo).
Item {
    id: kcm
    default property alias contents: holder.data
    implicitWidth: 700
    implicitHeight: 600
    Item {
        id: holder
        anchors.fill: parent
    }
    Component.onCompleted: {
        for (var i = 0; i < holder.children.length; ++i) {
            var c = holder.children[i];
            if (c.hasOwnProperty("implicitHeight"))
                c.width = Qt.binding(function() { return holder.width; });
        }
    }
}
