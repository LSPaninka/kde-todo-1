/*
 * TaskStore.qml
 *
 * Central data store for the Categorized ToDo plasmoid.
 *
 * Persistence: SQLite via QtQuick.LocalStorage 2.15 (see Database.qml).
 * Each mutation writes to SQLite immediately within an atomic
 * transaction — no debounce, no buffered file I/O. SQLite's own WAL
 * (or rollback journal) guarantees durability across reboots.
 *
 * Source of truth in memory:
 *   tasks    : array of plain JS objects (active tasks)
 *   archived : array of plain JS objects (archived tasks)
 *   version  : bump counter for QML binding refresh
 *
 * Task shape (same as before):
 *   {
 *     id, title, description, category, priority,
 *     done, createdAt, archivedAt,
 *     subtasks: [ { id, title, priority, done } ]
 *   }
 */

import QtQuick 2.15

QtObject {
    id: store

    // Injected from main.qml.
    property var plasmoid: null
    property var database: null

    property var tasks: []
    property var archived: []
    property int version: 0

    property int _nextId: 1
    property bool _loaded: false

    signal changed()

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function load() {
        if (!database) {
            console.warn("TaskStore.load: no Database");
            _loaded = true;
            _bump();
            return;
        }
        var data = database.loadAllTasks();
        tasks = data.active.map(_normalize);
        archived = data.archived.map(_normalize);
        _nextId = Math.max(1, data.maxId + 1);
        _loaded = true;
        _bump();
    }

    // Kept for API compatibility with the old caller chain — SQLite is
    // synchronous so there's nothing to flush.
    function flushNow() { /* no-op */ }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _bump() {
        version = version + 1;
        changed();
    }

    function _normalize(t) {
        return {
            id: t.id || 0,
            title: t.title || "",
            description: t.description || "",
            category: (t.category === undefined) ? 0 : (t.category | 0),
            priority: t.priority || "M",
            done: !!t.done,
            createdAt: t.createdAt || Date.now(),
            archivedAt: t.archivedAt || 0,
            subtasks: (t.subtasks || []).map(function(s) {
                return {
                    id: s.id || 0,
                    title: s.title || "",
                    priority: s.priority || "M",
                    done: !!s.done
                };
            })
        };
    }

    function _categoryName(i) {
        if (!plasmoid) return "category-" + i;
        var arr = plasmoid.configuration.categoryNames || [];
        return arr[i] || ("category-" + i);
    }

    // ------------------------------------------------------------------
    // Queries
    // ------------------------------------------------------------------

    function tasksForCategory(catIndex) {
        var out = [];
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category === catIndex) out.push(tasks[i]);
        }
        return out;
    }

    function pendingCountForCategory(catIndex) {
        var c = 0;
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category === catIndex && !tasks[i].done) c++;
        }
        return c;
    }

    function totalPending() {
        var c = 0;
        for (var i = 0; i < tasks.length; i++) if (!tasks[i].done) c++;
        return c;
    }

    function _indexOf(arr, id) {
        for (var i = 0; i < arr.length; i++) if (arr[i].id === id) return i;
        return -1;
    }

    function getTask(id) {
        var i = _indexOf(tasks, id);
        return (i >= 0) ? tasks[i] : null;
    }

    // ------------------------------------------------------------------
    // Mutations — each one writes to SQLite immediately.
    // ------------------------------------------------------------------

    function addTask(title, category, priority, description) {
        var t = _normalize({
            id: _nextId++,
            title: title,
            category: category | 0,
            priority: priority || "M",
            description: description || ""
        });
        tasks.push(t);
        if (database) database.saveTask(t, false);
        _bump();
        return t.id;
    }

    function updateTask(id, fields) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        var t = tasks[i];
        for (var k in fields) if (fields.hasOwnProperty(k)) t[k] = fields[k];
        tasks[i] = t;
        if (database) database.saveTask(t, false);
        _bump();
    }

    function toggleTaskDone(id) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        tasks[i].done = !tasks[i].done;
        if (database) database.saveTask(tasks[i], false);
        _bump();
    }

    function addSubtask(taskId, title, priority) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        tasks[i].subtasks.push({
            id: _nextId++,
            title: title,
            priority: priority || "M",
            done: false
        });
        if (database) database.saveTask(tasks[i], false);
        _bump();
    }

    function updateSubtask(taskId, subId, fields) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        var subs = tasks[i].subtasks;
        for (var j = 0; j < subs.length; j++) {
            if (subs[j].id === subId) {
                for (var k in fields) if (fields.hasOwnProperty(k)) subs[j][k] = fields[k];
                if (database) database.saveTask(tasks[i], false);
                _bump();
                return;
            }
        }
    }

    function toggleSubtaskDone(taskId, subId) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        var subs = tasks[i].subtasks;
        for (var j = 0; j < subs.length; j++) {
            if (subs[j].id === subId) {
                subs[j].done = !subs[j].done;
                if (database) database.saveTask(tasks[i], false);
                _bump();
                return;
            }
        }
    }

    function removeSubtask(taskId, subId) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        var subs = tasks[i].subtasks;
        for (var j = 0; j < subs.length; j++) {
            if (subs[j].id === subId) {
                subs.splice(j, 1);
                if (database) database.saveTask(tasks[i], false);
                _bump();
                return;
            }
        }
    }

    function archiveTask(id) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        var t = tasks[i];
        t.archivedAt = Date.now();
        t.done = true;
        archived.unshift(t);
        tasks.splice(i, 1);
        if (database) database.saveTask(t, true);
        _bump();
    }

    function restoreTask(id) {
        var i = _indexOf(archived, id);
        if (i < 0) return;
        var t = archived[i];
        t.archivedAt = 0;
        t.done = false;
        tasks.push(t);
        archived.splice(i, 1);
        if (database) database.saveTask(t, false);
        _bump();
    }

    function deleteArchived(id) {
        var i = _indexOf(archived, id);
        if (i < 0) return;
        archived.splice(i, 1);
        if (database) database.deleteTask(id);
        _bump();
    }

    function clearArchive() {
        archived = [];
        if (database) database.clearArchive();
        _bump();
    }

    // ------------------------------------------------------------------
    // Export / Import (used by the Export/Import dialogs in the UI)
    // ------------------------------------------------------------------

    function exportCategoryJson(catIndex) {
        var out = [];
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category === catIndex) out.push(tasks[i]);
        }
        return JSON.stringify({
            schema: "categorizedtodo.v1",
            exportedAt: Date.now(),
            category: catIndex,
            categoryName: _categoryName(catIndex),
            tasks: out
        }, null, 2);
    }

    function importCategoryJson(catIndex, jsonText) {
        var data = JSON.parse(jsonText);
        var src = null;
        if (Array.isArray(data)) src = data;
        else if (data && Array.isArray(data.tasks)) src = data.tasks;
        else throw new Error("Unrecognized JSON structure");

        var imported = 0;
        for (var i = 0; i < src.length; i++) {
            var raw = src[i];
            if (!raw || typeof raw !== "object") continue;
            var t = _normalize(raw);
            t.id = _nextId++;
            t.category = catIndex;
            t.archivedAt = 0;
            for (var j = 0; j < t.subtasks.length; j++) {
                t.subtasks[j].id = _nextId++;
            }
            tasks.push(t);
            if (database) database.saveTask(t, false);
            imported++;
        }
        _bump();
        return imported;
    }

    // ------------------------------------------------------------------
    // Category-count adjustments
    // ------------------------------------------------------------------

    function reassignOutOfRangeCategories(newCount) {
        var dirty = false;
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category >= newCount) {
                tasks[i].category = newCount - 1;
                if (database) database.saveTask(tasks[i], false);
                dirty = true;
            }
        }
        for (var j = 0; j < archived.length; j++) {
            if (archived[j].category >= newCount) {
                archived[j].category = newCount - 1;
                if (database) database.saveTask(archived[j], true);
                dirty = true;
            }
        }
        if (dirty) _bump();
    }

    // Kept for API compatibility — was only used to rewrite filename
    // slugs in the old JSON-file backend.
    function notifyCategoryNamesChanged() { /* no-op for SQLite backend */ }
}
