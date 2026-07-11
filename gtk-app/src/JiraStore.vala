/*
 * JiraStore.vala — read-only Jira Cloud REST v3 integration (ported from
 * JiraStore.qml). Fetches issues matching the configured JQL over HTTP
 * (libsoup3), normalizes them, groups them by the user-defined categories,
 * and caches the last successful response in SQLite.
 *
 * Auth: HTTP Basic with email + API token. Every fetch appends to an in-app
 * debug log (`last_debug_log`) surfaced in the preferences UI.
 */

namespace Ct {

    public class JiraStore : Object {
        public Config config { get; construct; }
        public Database database { get; construct; }

        public Gee.ArrayList<JiraIssue> issues { get; private set; }
        public bool loading { get; private set; default = false; }
        public string last_error { get; private set; default = ""; }
        public int64 last_fetched_at { get; private set; default = 0; }
        public int version { get; private set; default = 0; }
        public int selected_category { get; private set; default = 0; }

        public string last_debug_log { get; private set; default = ""; }

        public signal void changed ();
        public signal void fetch_finished (bool ok);
        public signal void category_requested (int index);

        private Soup.Session session;
        private uint refresh_source = 0;

        public JiraStore (Config config, Database database) {
            Object (config: config, database: database);
        }

        construct {
            issues = new Gee.ArrayList<JiraIssue> ();
            session = new Soup.Session ();
            session.timeout = 30;
        }

        public void init () {
            load_cache ();
            apply_refresh_schedule ();
        }

        private void bump () { version++; changed (); }

        // ---- refresh timer ---------------------------------------------
        public void apply_refresh_schedule () {
            if (refresh_source != 0) { Source.remove (refresh_source); refresh_source = 0; }
            int minutes = config.get_int ("jira-refresh-minutes");
            if (minutes > 0) {
                refresh_source = Timeout.add_seconds (minutes * 60, () => {
                    fetch.begin ();
                    return Source.CONTINUE;
                });
            }
        }

        // ---- cache ------------------------------------------------------
        private void load_cache () {
            int64 fetched;
            var rows = database.load_jira_json (out fetched);
            if (rows.size == 0) return;
            var outl = new Gee.ArrayList<JiraIssue> ();
            foreach (var raw in rows) {
                var iss = _issue_from_cache_json (raw);
                if (iss != null) outl.add (iss);
            }
            issues = outl;
            last_fetched_at = fetched;
            bump ();
        }

        private void save_cache () {
            string[] jsons = {};
            string[] keys = {};
            foreach (var iss in issues) {
                jsons += _issue_to_cache_json (iss);
                keys += iss.key;
            }
            database.save_jira_json (jsons, keys, last_fetched_at);
        }

        // ---- fetch ------------------------------------------------------
        public async void fetch () {
            var ts = new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S");
            _append_debug ("\n=== Fetch %s ===\n".printf (ts));

            if (loading) { _append_debug ("[abort] ya hay una carga en curso.\n"); return; }

            string site  = config.get_string ("jira-site").strip ().chomp ();
            while (site.has_suffix ("/")) site = site.substring (0, site.length - 1);
            string email = config.get_string ("jira-email").strip ();
            string token = config.get_string ("jira-token").strip ();
            string jql   = config.get_string ("jira-jql").strip ();
            int max = int.max (10, int.min (200, config.get_int ("jira-max-results")));

            string[] missing = {};
            if (site.length == 0) missing += "site";
            if (email.length == 0) missing += "email";
            if (token.length == 0) missing += "token";
            if (missing.length > 0) {
                last_error = "Faltan credenciales: " + string.joinv (", ", missing);
                _append_debug ("[abort] " + last_error + "\n");
                bump (); fetch_finished (false); return;
            }
            if (jql.length == 0) {
                last_error = "La consulta JQL está vacía.";
                _append_debug ("[abort] JQL vacío.\n");
                bump (); fetch_finished (false); return;
            }

            loading = true; last_error = ""; bump ();

            string fields = "summary,status,priority,issuetype,parent,updated,timetracking";
            string url = site + "/rest/api/3/search/jql?jql=" + Uri.escape_string (jql, null, true)
                       + "&maxResults=%d&fields=%s".printf (max, fields);
            _append_debug ("GET " + url + "\n");

            var msg = new Soup.Message ("GET", url);
            string auth = "Basic " + Base64.encode ((email + ":" + token).data);
            msg.request_headers.append ("Authorization", auth);
            msg.request_headers.append ("Accept", "application/json");

            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                uint status = msg.status_code;
                string body = (string) bytes.get_data ();
                _append_debug ("HTTP %u — %d bytes\n".printf (status, (int) bytes.get_size ()));
                loading = false;

                if (status == 200) {
                    _parse_success (body, site);
                } else {
                    last_error = _http_error (status, body);
                    _append_debug ("[!] " + last_error + "\n");
                    bump (); fetch_finished (false);
                }
            } catch (Error e) {
                loading = false;
                last_error = "Error de red: " + e.message;
                _append_debug ("[!] " + last_error + "\n");
                bump (); fetch_finished (false);
            }
        }

        private void _parse_success (string body, string site) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (body);
                var root = parser.get_root ().get_object ();
                var outl = new Gee.ArrayList<JiraIssue> ();
                if (root.has_member ("issues")) {
                    var arr = root.get_array_member ("issues");
                    for (uint i = 0; i < arr.get_length (); i++)
                        outl.add (_normalize (arr.get_object_element (i), site));
                }
                issues = outl;
                last_fetched_at = GLib.get_real_time () / 1000;
                last_error = "";
                save_cache ();
                _append_debug ("Resumen: %d issue(s).\n".printf (outl.size));
                bump ();
                fetch_finished (true);
            } catch (Error e) {
                last_error = "Error al parsear la respuesta: " + e.message;
                _append_debug ("[!] " + last_error + "\n");
                bump ();
                fetch_finished (false);
            }
        }

        private string _http_error (uint status, string body) {
            switch (status) {
                case 401: return "HTTP 401: credenciales rechazadas. Revisá email + token.";
                case 403: return "HTTP 403: el token no tiene permisos sobre este recurso.";
                case 404: return "HTTP 404: el endpoint no existe en este servidor.";
                case 410: return "HTTP 410: el endpoint fue removido por Atlassian. " + _extract_error (body);
                case 400: return "HTTP 400: " + _extract_error (body);
                case 0:   return "No se pudo contactar el servidor. ¿La URL es correcta y hay conexión?";
                default:  return "HTTP %u: %s".printf (status, _extract_error (body));
            }
        }

        // ---- test connection -------------------------------------------
        public async bool test_connection (string site_in, string email_in, string token_in, out string message) {
            string site = site_in.strip ();
            while (site.has_suffix ("/")) site = site.substring (0, site.length - 1);
            string email = email_in.strip ();
            string token = token_in.strip ();
            if (site.length == 0 || email.length == 0 || token.length == 0) {
                message = "Completá los tres campos antes de probar.";
                return false;
            }
            var msg = new Soup.Message ("GET", site + "/rest/api/3/myself");
            msg.request_headers.append ("Authorization", "Basic " + Base64.encode ((email + ":" + token).data));
            msg.request_headers.append ("Accept", "application/json");
            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code == 200) {
                    string name = email;
                    try {
                        var p = new Json.Parser (); p.load_from_data ((string) bytes.get_data ());
                        var o = p.get_root ().get_object ();
                        if (o.has_member ("displayName")) name = o.get_string_member ("displayName");
                    } catch (Error e) { }
                    message = "OK — autenticado como %s".printf (name);
                    return true;
                }
                message = _http_error (msg.status_code, (string) bytes.get_data ());
                return false;
            } catch (Error e) {
                message = "Error de red: " + e.message;
                return false;
            }
        }

        // ---- issue detail ----------------------------------------------
        // Returns a JSON string of the detail (the UI parses what it needs),
        // or null on failure with `err` set.
        public async Json.Object? fetch_issue_detail (string key, out string err) {
            err = "";
            string site  = config.get_string ("jira-site").strip ();
            while (site.has_suffix ("/")) site = site.substring (0, site.length - 1);
            string email = config.get_string ("jira-email").strip ();
            string token = config.get_string ("jira-token").strip ();
            if (site.length == 0 || email.length == 0 || token.length == 0) {
                err = "Faltan credenciales."; return null;
            }
            string fields = "summary,status,priority,issuetype,parent,assignee,description,timetracking,created,updated,comment";
            string url = site + "/rest/api/3/issue/" + Uri.escape_string (key, null, true) + "?fields=" + fields;
            var msg = new Soup.Message ("GET", url);
            msg.request_headers.append ("Authorization", "Basic " + Base64.encode ((email + ":" + token).data));
            msg.request_headers.append ("Accept", "application/json");
            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code == 200) {
                    var p = new Json.Parser (); p.load_from_data ((string) bytes.get_data ());
                    return p.get_root ().get_object ();
                }
                err = _http_error (msg.status_code, (string) bytes.get_data ());
                return null;
            } catch (Error e) {
                err = "Error de red: " + e.message;
                return null;
            }
        }

        // ---- status transitions ----------------------------------------
        //   GET  /rest/api/3/issue/{key}/transitions → available transitions
        //   POST /rest/api/3/issue/{key}/transitions → apply one
        public async Gee.ArrayList<JiraTransition> fetch_transitions (string key) {
            var outl = new Gee.ArrayList<JiraTransition> ();
            string site  = config.get_string ("jira-site").strip ();
            while (site.has_suffix ("/")) site = site.substring (0, site.length - 1);
            string email = config.get_string ("jira-email").strip ();
            string token = config.get_string ("jira-token").strip ();
            if (site.length == 0 || email.length == 0 || token.length == 0) return outl;
            var msg = new Soup.Message ("GET",
                site + "/rest/api/3/issue/" + Uri.escape_string (key, null, true) + "/transitions");
            msg.request_headers.append ("Authorization", "Basic " + Base64.encode ((email + ":" + token).data));
            msg.request_headers.append ("Accept", "application/json");
            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code != 200) return outl;
                var p = new Json.Parser (); p.load_from_data ((string) bytes.get_data ());
                var root = p.get_root ().get_object ();
                if (!root.has_member ("transitions")) return outl;
                var arr = root.get_array_member ("transitions");
                for (uint i = 0; i < arr.get_length (); i++) {
                    var t = arr.get_object_element (i);
                    var to = _obj (t, "to");
                    outl.add (new JiraTransition.with (
                        _str (t, "id"), _str (t, "name"),
                        _str (to, "name"), _str (_obj (to, "statusCategory"), "colorName")));
                }
            } catch (Error e) { _append_debug ("[!] transitions: " + e.message + "\n"); }
            return outl;
        }

        public async bool transition_issue (string key, string transition_id, out string err) {
            err = "";
            string site  = config.get_string ("jira-site").strip ();
            while (site.has_suffix ("/")) site = site.substring (0, site.length - 1);
            string email = config.get_string ("jira-email").strip ();
            string token = config.get_string ("jira-token").strip ();
            if (site.length == 0 || email.length == 0 || token.length == 0) { err = "Faltan credenciales."; return false; }
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("transition");
            b.begin_object (); b.set_member_name ("id"); b.add_string_value (transition_id); b.end_object ();
            b.end_object ();
            var gen = new Json.Generator (); gen.set_root (b.get_root ());
            var msg = new Soup.Message ("POST",
                site + "/rest/api/3/issue/" + Uri.escape_string (key, null, true) + "/transitions");
            msg.request_headers.append ("Authorization", "Basic " + Base64.encode ((email + ":" + token).data));
            msg.request_headers.append ("Accept", "application/json");
            msg.set_request_body_from_bytes ("application/json", new Bytes (gen.to_data (null).data));
            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code == 204 || msg.status_code == 200) return true;
                err = _extract_error ((string) bytes.get_data ());
                if (err.length == 0) err = "HTTP %u".printf (msg.status_code);
                return false;
            } catch (Error e) { err = "Error de red: " + e.message; return false; }
        }

        // Consumed-hours ratio for the progress bar: min(spent, original)/original,
        // clamped to [0,1]. Returns -1 when there is no estimate to show.
        public static double consumed_ratio (int original_sec, int spent_sec) {
            if (original_sec <= 0) return -1;
            double r = (double) int.min (spent_sec, original_sec) / (double) original_sec;
            return r.clamp (0.0, 1.0);
        }

        public static string fmt_seconds (int s) {
            if (s <= 0) return "0h";
            int hh = s / 3600;
            int mm = (s % 3600) / 60;
            var parts = new string[0];
            if (hh > 0) parts += "%dh".printf (hh);
            if (mm > 0) parts += "%dm".printf (mm);
            return parts.length > 0 ? string.joinv (" ", parts) : "0h";
        }

        // Flatten an ADF node tree to plain text.
        public static string adf_to_text (Json.Node? node) {
            if (node == null) return "";
            var sb = new StringBuilder ();
            _adf_walk (node, sb);
            string s = sb.str;
            // collapse 3+ newlines, trim trailing spaces on lines
            try {
                var re1 = new Regex ("\n{3,}");
                s = re1.replace (s, s.length, 0, "\n\n");
            } catch (Error e) { }
            return s.strip ();
        }

        private static void _adf_walk (Json.Node node, StringBuilder sb) {
            if (node.get_node_type () != Json.NodeType.OBJECT) return;
            var o = node.get_object ();
            string type = o.has_member ("type") ? o.get_string_member ("type") : "";
            if (type == "text") { if (o.has_member ("text")) sb.append (o.get_string_member ("text")); return; }
            if (type == "hardBreak") { sb.append ("\n"); return; }
            if (o.has_member ("content")) {
                var arr = o.get_array_member ("content");
                for (uint i = 0; i < arr.get_length (); i++)
                    _adf_walk (arr.get_element (i), sb);
            }
            if (type == "paragraph" || type == "heading" || type == "listItem" || type == "blockquote")
                sb.append ("\n");
        }

        // ---- category filtering ----------------------------------------
        public Gee.ArrayList<JiraIssue> issues_by_category (int cat) {
            var outl = new Gee.ArrayList<JiraIssue> ();
            foreach (var iss in issues)
                if (matches_category (iss, cat)) outl.add (iss);
            return outl;
        }

        public int count_by_category (int cat) {
            int c = 0;
            foreach (var iss in issues)
                if (matches_category (iss, cat)) c++;
            return c;
        }

        public bool matches_category (JiraIssue iss, int cat) {
            string field = config.strv_at ("jira-category-filter-fields", cat, "").strip ();
            string value = config.strv_at ("jira-category-filter-values", cat, "").strip ();
            if (field.length == 0 || value.length == 0) return true;
            string actual = _issue_field (iss, field);
            if (actual.length == 0) return false;
            string got = actual.strip ().down ();
            foreach (var raw in value.split_set (";,")) {
                string a = raw.strip ().down ();
                if (a.length > 0 && a == got) return true;
            }
            return false;
        }

        private string _issue_field (JiraIssue iss, string field) {
            switch (field) {
                case "statusCategory": return iss.status_cat;
                case "status":         return iss.status_name;
                case "issuetype":      return iss.issuetype;
                case "priority":       return iss.priority;
            }
            return "";
        }

        public int total_count () { return issues.size; }

        public void request_category (int index) {
            selected_category = index;
            category_requested (index);
        }

        // Optional per-status chip color override (config lists).
        public string? status_override_color (string status_name) {
            var names = config.get_strv ("jira-status-names");
            var colors = config.get_strv ("jira-status-colors");
            for (int i = 0; i < names.length && i < colors.length; i++) {
                if (names[i].strip ().down () == status_name.strip ().down () && colors[i].strip ().length > 0)
                    return colors[i].strip ();
            }
            return null;
        }

        // ---- normalization / json helpers ------------------------------
        private JiraIssue _normalize (Json.Object raw, string site) {
            var f = raw.has_member ("fields") ? raw.get_object_member ("fields") : new Json.Object ();
            var iss = new JiraIssue ();
            iss.key = _str (raw, "key");
            iss.summary = _str (f, "summary");
            var status = _obj (f, "status");
            iss.status_name = _str (status, "name");
            var sc = _obj (status, "statusCategory");
            iss.status_cat = _str_def (sc, "key", "undefined");
            iss.status_color = _str (sc, "colorName");
            iss.priority = _str (_obj (f, "priority"), "name");
            var it = _obj (f, "issuetype");
            iss.issuetype = _str (it, "name");
            iss.is_subtask = it.has_member ("subtask") && it.get_boolean_member ("subtask");
            var parent = _obj (f, "parent");
            iss.parent_key = _str (parent, "key");
            iss.parent_summary = _str (_obj (parent, "fields"), "summary");
            var tt = _obj (f, "timetracking");
            iss.original_sec = _int (tt, "originalEstimateSeconds");
            iss.spent_sec = _int (tt, "timeSpentSeconds");
            iss.updated = _str (f, "updated");
            iss.url = site + "/browse/" + iss.key;
            return iss;
        }

        private string _issue_to_cache_json (JiraIssue iss) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("key"); b.add_string_value (iss.key);
            b.set_member_name ("summary"); b.add_string_value (iss.summary);
            b.set_member_name ("statusName"); b.add_string_value (iss.status_name);
            b.set_member_name ("statusCat"); b.add_string_value (iss.status_cat);
            b.set_member_name ("statusColor"); b.add_string_value (iss.status_color);
            b.set_member_name ("priority"); b.add_string_value (iss.priority);
            b.set_member_name ("issuetype"); b.add_string_value (iss.issuetype);
            b.set_member_name ("isSubtask"); b.add_boolean_value (iss.is_subtask);
            b.set_member_name ("parentKey"); b.add_string_value (iss.parent_key);
            b.set_member_name ("parentSummary"); b.add_string_value (iss.parent_summary);
            b.set_member_name ("originalSec"); b.add_int_value (iss.original_sec);
            b.set_member_name ("spentSec"); b.add_int_value (iss.spent_sec);
            b.set_member_name ("updated"); b.add_string_value (iss.updated);
            b.set_member_name ("url"); b.add_string_value (iss.url);
            b.end_object ();
            var g = new Json.Generator (); g.set_root (b.get_root ());
            return g.to_data (null);
        }

        private JiraIssue? _issue_from_cache_json (string raw) {
            try {
                var p = new Json.Parser (); p.load_from_data (raw);
                var o = p.get_root ().get_object ();
                var iss = new JiraIssue ();
                iss.key = _str (o, "key");
                iss.summary = _str (o, "summary");
                iss.status_name = _str (o, "statusName");
                iss.status_cat = _str (o, "statusCat");
                iss.status_color = _str (o, "statusColor");
                iss.priority = _str (o, "priority");
                iss.issuetype = _str (o, "issuetype");
                iss.is_subtask = o.has_member ("isSubtask") && o.get_boolean_member ("isSubtask");
                iss.parent_key = _str (o, "parentKey");
                iss.parent_summary = _str (o, "parentSummary");
                iss.original_sec = _int (o, "originalSec");
                iss.spent_sec = _int (o, "spentSec");
                iss.updated = _str (o, "updated");
                iss.url = _str (o, "url");
                return iss;
            } catch (Error e) { return null; }
        }

        // ---- generic json accessors ------------------------------------
        internal static string _str (Json.Object o, string key) {
            return o.has_member (key) && o.get_member (key).get_node_type () == Json.NodeType.VALUE
                   ? (o.get_string_member (key) ?? "") : "";
        }
        internal static string _str_def (Json.Object o, string key, string def) {
            string v = _str (o, key);
            return v.length > 0 ? v : def;
        }
        internal static Json.Object _obj (Json.Object o, string key) {
            if (o.has_member (key) && o.get_member (key).get_node_type () == Json.NodeType.OBJECT)
                return o.get_object_member (key);
            return new Json.Object ();
        }
        internal static int _int (Json.Object o, string key) {
            if (o.has_member (key) && o.get_member (key).get_node_type () == Json.NodeType.VALUE) {
                var n = o.get_member (key);
                if (n.get_value_type () == typeof (int64)) return (int) o.get_int_member (key);
                if (n.get_value_type () == typeof (double)) return (int) o.get_double_member (key);
            }
            return 0;
        }

        private static string _extract_error (string body) {
            if (body.length == 0) return "";
            try {
                var p = new Json.Parser (); p.load_from_data (body);
                var o = p.get_root ().get_object ();
                if (o.has_member ("errorMessages")) {
                    var arr = o.get_array_member ("errorMessages");
                    var parts = new string[0];
                    for (uint i = 0; i < arr.get_length (); i++) parts += arr.get_string_element (i);
                    if (parts.length > 0) return string.joinv ("; ", parts);
                }
                if (o.has_member ("message")) return o.get_string_member ("message");
            } catch (Error e) { }
            return body.length > 200 ? body.substring (0, 200) : body;
        }

        private void _append_debug (string line) {
            string next = last_debug_log + line;
            if (next.length > 80000)
                next = "[…log truncado…]\n" + next.substring (next.length - 40000);
            last_debug_log = next;
        }

        public void clear_debug_log () { last_debug_log = ""; bump (); }
    }
}
