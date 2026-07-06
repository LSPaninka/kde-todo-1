/*
 * Models.vala — plain data objects shared across the stores and the UI.
 *
 * Ported from the QML plasmoid's in-memory model (plain JS objects). A Task
 * maps 1:1 to a row in the `tasks` SQLite table plus its `subtasks` rows and,
 * optionally, one Notion page (the *-page-id / notion-* fields).
 */

namespace Ct {

    // Priority levels, smallest → largest. Mirrors the QML PriorityBadge set.
    public const string[] PRIORITIES = { "XS", "S", "M", "L", "XL" };

    public string priority_color (string level) {
        switch (level) {
            case "XS": return "#95a5a6";
            case "S":  return "#3498db";
            case "M":  return "#2ecc71";
            case "L":  return "#f39c12";
            case "XL": return "#e74c3c";
            default:   return "#2ecc71";
        }
    }

    public class Subtask : Object {
        public int64 id { get; set; default = 0; }
        public string title { get; set; default = ""; }
        public string priority { get; set; default = "M"; }
        public bool done { get; set; default = false; }

        public Subtask.with (int64 id, string title, string priority, bool done) {
            this.id = id;
            this.title = title;
            this.priority = priority;
            this.done = done;
        }
    }

    public class Task : Object {
        public int64 id { get; set; default = 0; }
        public string title { get; set; default = ""; }
        public string description { get; set; default = ""; }
        public int category { get; set; default = 0; }
        public string priority { get; set; default = "M"; }
        public bool done { get; set; default = false; }
        public int64 created_at { get; set; default = 0; }
        public int64 archived_at { get; set; default = 0; }

        // Notion two-way sync bookkeeping (see NotionSyncStore).
        public string notion_page_id { get; set; default = ""; }
        public int64 updated_at { get; set; default = 0; }
        public string notion_last_edited { get; set; default = ""; }
        public int64 notion_synced_at { get; set; default = 0; }

        public Gee.ArrayList<Subtask> subtasks { get; set; }

        construct {
            subtasks = new Gee.ArrayList<Subtask> ();
            if (created_at == 0)
                created_at = GLib.get_real_time () / 1000;
        }

        public int pending_subtasks () {
            int c = 0;
            foreach (var s in subtasks)
                if (!s.done) c++;
            return c;
        }
    }

    // A read-only Jira issue (list view + detail share most fields).
    public class JiraIssue : Object {
        public string key { get; set; default = ""; }
        public string summary { get; set; default = ""; }
        public string status_name { get; set; default = ""; }
        public string status_cat { get; set; default = ""; }
        public string status_color { get; set; default = ""; }
        public string priority { get; set; default = ""; }
        public string issuetype { get; set; default = ""; }
        public bool is_subtask { get; set; default = false; }
        public string parent_key { get; set; default = ""; }
        public string parent_summary { get; set; default = ""; }
        public string updated { get; set; default = ""; }
        public string url { get; set; default = ""; }
    }

    // A read-only GitHub Projects (V2) item.
    public class GhItem : Object {
        public string id { get; set; default = ""; }
        public string item_type { get; set; default = ""; }   // Issue/PullRequest/DraftIssue
        public string title { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public int number { get; set; default = 0; }
        public string state { get; set; default = ""; }       // OPEN/CLOSED/MERGED/DRAFT
        public bool is_draft { get; set; default = false; }
        public string repo { get; set; default = ""; }
        public string updated { get; set; default = ""; }
        public string status_name { get; set; default = ""; }
    }
}
