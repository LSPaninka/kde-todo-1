/*
 * RingGauge.qml - circular donut gauge with center percentage label.
 *
 * Features:
 *   - Fill-in animation from 0 → value on startFill() (used when the
 *     popup is opened so the rings draw themselves up to the current
 *     percentage with an OutQuart easing).
 *   - Optional fade-loop on the ring color (used by the Horas ring): a
 *     SequentialAnimation cycles `animatedColor` between baseColor and
 *     paleColor at a duration controlled by `intermittent` (1 s vs
 *     1.5 s cycle, plus a hold at the base color).
 *   - Anti-aliased arc drawn with Canvas's lineCap=round.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: ring

    // Inputs
    property real value: 0            // target percentage 0..100
    property color baseColor: "#81C784"
    property color paleColor: "#C8E6C9"
    property color trackColor: "#2a2a2a"
    property real thickness: 12
    property real diameter: 110

    // Loop animation (for Horas ring)
    property bool useFadeLoop: false
    property bool intermittent: false   // faster cycle when true
    property string centerLabel: Math.round(displayValue) + "%"

    // Internal animation state
    property real displayValue: 0       // animated 0..value during startFill
    property color animatedColor: baseColor

    implicitWidth: diameter
    implicitHeight: diameter

    function startFill() {
        fillAnim.stop();
        displayValue = 0;
        fillAnim.start();
    }

    NumberAnimation {
        id: fillAnim
        target: ring
        property: "displayValue"
        from: 0
        to: ring.value
        duration: 1500
        easing.type: Easing.OutQuart
    }

    // When the value changes outside of an animation (e.g. fresh fetch),
    // bring the display up to the new target.
    onValueChanged: {
        if (!fillAnim.running) {
            displayValue = value;
            canvas.requestPaint();
        }
    }
    onDisplayValueChanged: canvas.requestPaint()
    onAnimatedColorChanged: canvas.requestPaint()
    onBaseColorChanged: {
        // Keep animatedColor in sync with the latest baseColor when the
        // fade loop isn't running.
        if (!fadeLoop.running) animatedColor = baseColor;
        canvas.requestPaint();
    }
    onTrackColorChanged: canvas.requestPaint()

    // Fade loop — only one of these is active depending on `useFadeLoop`.
    SequentialAnimation {
        id: fadeLoop
        loops: Animation.Infinite
        running: ring.useFadeLoop
        PauseAnimation { duration: ring.intermittent ? 1000 : 3000 }
        ColorAnimation {
            target: ring; property: "animatedColor"
            to: ring.paleColor
            duration: ring.intermittent ? 1000 : 1500
        }
        ColorAnimation {
            target: ring; property: "animatedColor"
            to: ring.baseColor
            duration: ring.intermittent ? 1000 : 1500
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            var cx = width / 2;
            var cy = height / 2;
            var r  = (Math.min(width, height) - ring.thickness) / 2;

            // Background track (full circle).
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.strokeStyle = ring.trackColor;
            ctx.lineWidth = ring.thickness;
            ctx.lineCap = "round";
            ctx.stroke();

            // Foreground arc.
            var v = Math.max(0, Math.min(100, ring.displayValue));
            if (v > 0) {
                var startA = -Math.PI / 2;
                var endA   = startA + (v / 100) * Math.PI * 2;
                ctx.beginPath();
                ctx.arc(cx, cy, r, startA, endA);
                ctx.strokeStyle = ring.animatedColor;
                ctx.lineWidth = ring.thickness;
                ctx.lineCap = "round";
                ctx.stroke();
            }
        }
    }

    // Center label.
    PlasmaComponents3.Label {
        anchors.centerIn: parent
        text: ring.centerLabel
        font.bold: true
        font.pixelSize: Math.round(ring.diameter * 0.22)
    }
}
