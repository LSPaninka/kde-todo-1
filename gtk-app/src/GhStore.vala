/*
 * GhStore.vala — read-only GitHub Projects (V2) integration (ported from
 * GhStore.qml). Fetches a project's items over the GraphQL v4 API
 * (api.github.com/graphql) with a Personal Access Token, normalizes them and
 * groups them by user-defined categories. Caches the last response in SQLite.
 */

namespace Ct {

    public class GhStore : Object {
        public Config config { get; construct; }
        public Database database { get; construct; }

        public Gee.ArrayList<GhItem> items { get; private set; }
        public bool loading { get; private set; default = false; }
        public string last_error { get; private set; default = ""; }
        public int64 last_fetched_at { get; private set; default = 0; }
        public int version { get; private set; default = 0; }
        public string[] status_options { get; private set; default = {}; }

        public string last_debug_log { get; private set; default = ""; }

        public signal void changed ();
        public signal void fetch_finished (bool ok);

        private Soup.Session session;
        private uint refresh_source = 0;

        public GhStore (Config config, Database database) {
            Object (config: config, database: database);
        }

        construct {
            items = new Gee.ArrayList<GhItem> ();
            session = new Soup.Session ();
            session.timeout = 30;
        }

        public void init () {
            load_cache ();
            apply_refresh_schedule ();
        }

        private void bump () { version++; changed (); }

        public void apply_refresh_schedule () {
            if (refresh_source != 0) { Source.remove (refresh_source); refresh_source = 0; }
            int minutes = config.get_int ("gh-refresh-minutes");
            if (minutes > 0)
                refresh_source = Timeout.add_seconds (minutes * 60, () => { fetch.begin (); return Source.CONTINUE; });
        }

        private void load_cache () {
            int64 fetched;
            var rows = database.load_gh_json (out fetched);
            if (rows.size == 0) return;
            var outl = new Gee.ArrayList<GhItem> ();
            foreach (var raw in rows) {
                var it = _item_from_cache_json (raw);
                if (it != null) outl.add (it);
            }
            items = outl;
            last_fetched_at = fetched;
            bump ();
        }

        private void save_cache () {
            string[] jsons = {};
            string[] ids = {};
            foreach (var it in items) {
                jsons += _item_to_cache_json (it);
                ids += it.id;
            }
            database.save_gh_json (jsons, ids, last_fetched_at);
        }

        public async void fetch () {
            var ts = new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S");
            _append_debug ("\n=== Fetch %s ===\n".printf (ts));
            if (loading) { _append_debug ("[abort] ya hay una carga en curso.\n"); return; }

            string token = config.get_string ("gh-token").strip ();
            string owner = config.get_string ("gh-owner").strip ();
            string owner_type = config.get_string ("gh-owner-type").strip ().down ();
            int number = config.get_int ("gh-project-number");
            int max = int.max (10, int.min (300, config.get_int ("gh-max-results")));

            string[] missing = {};
            if (token.length == 0) missing += "token";
            if (owner.length == 0) missing += "owner";
            if (number == 0) missing += "project number";
            if (missing.length > 0) {
                last_error = "Faltan campos: " + string.joinv (", ", missing);
                _append_debug ("[abort] " + last_error + "\n");
                bump (); fetch_finished (false); return;
            }
            if (owner_type != "user" && owner_type != "organization") {
                last_error = "ownerType debe ser 'user' u 'organization'.";
                _append_debug ("[abort] " + last_error + "\n");
                bump (); fetch_finished (false); return;
            }

            loading = true; last_error = ""; bump ();

            string selector = (owner_type == "organization") ? "organization" : "user";
            string query =
                "query($login: String!, $number: Int!, $first: Int!) {" +
                "  " + selector + "(login: $login) {" +
                "    projectV2(number: $number) {" +
                "      title" +
                "      items(first: $first) {" +
                "        totalCount" +
                "        nodes {" +
                "          id type updatedAt" +
                "          content {" +
                "            __typename" +
                "            ... on Issue { number title url state repository { nameWithOwner } }" +
                "            ... on PullRequest { number title url state isDraft repository { nameWithOwner } }" +
                "            ... on DraftIssue { title body }" +
                "          }" +
                "          fieldValues(first: 20) {" +
                "            nodes {" +
                "              __typename" +
                "              ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2SingleSelectField { name } } }" +
                "              ... on ProjectV2ItemFieldTextValue { text field { ... on ProjectV2Field { name } } }" +
                "              ... on ProjectV2ItemFieldNumberValue { number field { ... on ProjectV2Field { name } } }" +
                "              ... on ProjectV2ItemFieldIterationValue { title field { ... on ProjectV2IterationField { name } } }" +
                "            }" +
                "          }" +
                "        }" +
                "      }" +
                "    }" +
                "  }" +
                "}";

            var vb = new Json.Builder ();
            vb.begin_object ();
            vb.set_member_name ("query"); vb.add_string_value (query);
            vb.set_member_name ("variables");
            vb.begin_object ();
            vb.set_member_name ("login"); vb.add_string_value (owner);
            vb.set_member_name ("number"); vb.add_int_value (number);
            vb.set_member_name ("first"); vb.add_int_value (max);
            vb.end_object ();
            vb.end_object ();
            var gen = new Json.Generator (); gen.set_root (vb.get_root ());
            string body = gen.to_data (null);

            _append_debug ("POST https://api.github.com/graphql\n");

            var msg = new Soup.Message ("POST", "https://api.github.com/graphql");
            msg.request_headers.append ("Authorization", "Bearer " + token);
            msg.request_headers.append ("Accept", "application/json");
            msg.request_headers.append ("User-Agent", "categorized-todo-gtk");
            msg.set_request_body_from_bytes ("application/json", new Bytes (body.data));

            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                uint status = msg.status_code;
                string resp = (string) bytes.get_data ();
                _append_debug ("HTTP %u — %d bytes\n".printf (status, (int) bytes.get_size ()));
                loading = false;

                if (status == 200) {
                    _parse_success (resp, owner, number);
                } else {
                    last_error = _http_error (status, resp);
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

        private void _parse_success (string resp, string owner, int number) {
            try {
                var parser = new Json.Parser (); parser.load_from_data (resp);
                var root = parser.get_root ().get_object ();
                if (root.has_member ("errors")) {
                    var errs = root.get_array_member ("errors");
                    var parts = new string[0];
                    for (uint i = 0; i < errs.get_length (); i++) {
                        var eo = errs.get_object_element (i);
                        parts += eo.has_member ("message") ? eo.get_string_member ("message") : "error";
                    }
                    last_error = "GraphQL: " + string.joinv ("; ", parts);
                    _append_debug ("[!] " + last_error + "\n");
                    bump (); fetch_finished (false); return;
                }
                var data = JiraStore._obj (root, "data");
                Json.Object owner_node = new Json.Object ();
                if (data.has_member ("user") && data.get_member ("user").get_node_type () == Json.NodeType.OBJECT)
                    owner_node = data.get_object_member ("user");
                else if (data.has_member ("organization") && data.get_member ("organization").get_node_type () == Json.NodeType.OBJECT)
                    owner_node = data.get_object_member ("organization");

                if (!owner_node.has_member ("projectV2") ||
                    owner_node.get_member ("projectV2").get_node_type () != Json.NodeType.OBJECT) {
                    last_error = "No se encontró el proyecto para %s #%d".printf (owner, number);
                    _append_debug ("[!] " + last_error + "\n");
                    bump (); fetch_finished (false); return;
                }
                var project = owner_node.get_object_member ("projectV2");
                var items_obj = JiraStore._obj (project, "items");
                bool include_closed = config.get_bool ("gh-include-closed");
                string status_field = config.get_string ("gh-status-field").strip ();
                if (status_field.length == 0) status_field = "Status";

                var outl = new Gee.ArrayList<GhItem> ();
                var seen = new Gee.HashSet<string> ();
                if (items_obj.has_member ("nodes")) {
                    var nodes = items_obj.get_array_member ("nodes");
                    for (uint i = 0; i < nodes.get_length (); i++) {
                        if (nodes.get_element (i).get_node_type () != Json.NodeType.OBJECT) continue;
                        var it = _normalize (nodes.get_object_element (i), status_field);
                        if (!include_closed && (it.state == "CLOSED" || it.state == "MERGED")) continue;
                        if (it.status_name.length > 0) seen.add (it.status_name);
                        outl.add (it);
                    }
                }
                items = outl;
                var opts = new string[0];
                foreach (var st in seen) opts += st;
                status_options = opts;
                last_fetched_at = GLib.get_real_time () / 1000;
                last_error = "";
                save_cache ();
                _append_debug ("Resumen: %d item(s).\n".printf (outl.size));
                bump ();
                fetch_finished (true);
            } catch (Error e) {
                last_error = "Error al parsear la respuesta: " + e.message;
                _append_debug ("[!] " + last_error + "\n");
                bump (); fetch_finished (false);
            }
        }

        private string _http_error (uint status, string body) {
            switch (status) {
                case 401: return "HTTP 401: token rechazado. Revisá scopes del PAT.";
                case 403: return "HTTP 403: sin permisos. ¿Le diste acceso a Projects al token?";
                case 0:   return "No se pudo contactar api.github.com. ¿Hay conexión?";
                default:  return "HTTP %u: %s".printf (status, _extract_error (body));
            }
        }

        public async bool test_connection (string token_in, out string message) {
            string token = token_in.strip ();
            if (token.length == 0) { message = "Completá el token antes de probar."; return false; }
            var msg = new Soup.Message ("GET", "https://api.github.com/user");
            msg.request_headers.append ("Authorization", "Bearer " + token);
            msg.request_headers.append ("Accept", "application/vnd.github+json");
            msg.request_headers.append ("User-Agent", "categorized-todo-gtk");
            try {
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.status_code == 200) {
                    string login = "?";
                    try {
                        var p = new Json.Parser (); p.load_from_data ((string) bytes.get_data ());
                        var o = p.get_root ().get_object ();
                        if (o.has_member ("login")) login = o.get_string_member ("login");
                    } catch (Error e) { }
                    message = "OK — autenticado como %s".printf (login);
                    return true;
                }
                message = _http_error (msg.status_code, (string) bytes.get_data ());
                return false;
            } catch (Error e) {
                message = "Error de red: " + e.message;
                return false;
            }
        }

        // ---- category filtering ----------------------------------------
        public Gee.ArrayList<GhItem> items_by_category (int cat) {
            var outl = new Gee.ArrayList<GhItem> ();
            foreach (var it in items)
                if (matches_category (it, cat)) outl.add (it);
            return outl;
        }

        public int count_by_category (int cat) {
            int c = 0;
            foreach (var it in items)
                if (matches_category (it, cat)) c++;
            return c;
        }

        public bool matches_category (GhItem it, int cat) {
            string field = config.strv_at ("gh-category-filter-fields", cat, "").strip ();
            string value = config.strv_at ("gh-category-filter-values", cat, "").strip ();
            if (field.length == 0 || value.length == 0) return true;
            string actual = _item_field (it, field);
            if (actual.length == 0) return false;
            string got = actual.strip ().down ();
            foreach (var raw in value.split_set (";,")) {
                string a = raw.strip ().down ();
                if (a.length > 0 && a == got) return true;
            }
            return false;
        }

        private string _item_field (GhItem it, string field) {
            switch (field) {
                case "status": return it.status_name;
                case "type":   return it.item_type;
                case "state":  return it.state;
                case "repo":   return it.repo;
            }
            return "";
        }

        public int total_count () { return items.size; }

        // ---- normalization ---------------------------------------------
        private GhItem _normalize (Json.Object node, string status_field) {
            var content = JiraStore._obj (node, "content");
            string tn = content.has_member ("__typename") ? content.get_string_member ("__typename")
                        : JiraStore._str (node, "type");
            string type = tn;
            if (type == "ISSUE" || type == "Issue") type = "Issue";
            else if (type == "PULL_REQUEST" || type == "PullRequest") type = "PullRequest";
            else if (type == "DRAFT_ISSUE" || type == "DraftIssue") type = "DraftIssue";

            string status_name = "";
            var fv = JiraStore._obj (node, "fieldValues");
            if (fv.has_member ("nodes")) {
                var arr = fv.get_array_member ("nodes");
                for (uint i = 0; i < arr.get_length (); i++) {
                    if (arr.get_element (i).get_node_type () != Json.NodeType.OBJECT) continue;
                    var vo = arr.get_object_element (i);
                    string tname = vo.has_member ("__typename") ? vo.get_string_member ("__typename") : "";
                    var fld = JiraStore._obj (vo, "field");
                    string fname = JiraStore._str (fld, "name");
                    if (fname.length == 0) continue;
                    if (tname == "ProjectV2ItemFieldSingleSelectValue"
                        && fname.down () == status_field.down ())
                        status_name = JiraStore._str (vo, "name");
                }
            }

            var it = new GhItem ();
            it.id = JiraStore._str (node, "id");
            it.item_type = type;
            it.title = JiraStore._str_def (content, "title", "(sin título)");
            it.url = JiraStore._str (content, "url");
            it.number = content.has_member ("number") ? (int) content.get_int_member ("number") : 0;
            string state = JiraStore._str (content, "state");
            bool is_draft = content.has_member ("isDraft") && content.get_boolean_member ("isDraft");
            if (type == "PullRequest" && is_draft) state = "DRAFT";
            if (type == "DraftIssue" && state.length == 0) state = "DRAFT";
            it.state = state;
            it.is_draft = is_draft;
            it.repo = JiraStore._str (JiraStore._obj (content, "repository"), "nameWithOwner");
            it.updated = JiraStore._str (node, "updatedAt");
            it.status_name = status_name;
            return it;
        }

        private string _item_to_cache_json (GhItem it) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("id"); b.add_string_value (it.id);
            b.set_member_name ("type"); b.add_string_value (it.item_type);
            b.set_member_name ("title"); b.add_string_value (it.title);
            b.set_member_name ("url"); b.add_string_value (it.url);
            b.set_member_name ("number"); b.add_int_value (it.number);
            b.set_member_name ("state"); b.add_string_value (it.state);
            b.set_member_name ("isDraft"); b.add_boolean_value (it.is_draft);
            b.set_member_name ("repo"); b.add_string_value (it.repo);
            b.set_member_name ("updated"); b.add_string_value (it.updated);
            b.set_member_name ("statusName"); b.add_string_value (it.status_name);
            b.end_object ();
            var g = new Json.Generator (); g.set_root (b.get_root ());
            return g.to_data (null);
        }

        private GhItem? _item_from_cache_json (string raw) {
            try {
                var p = new Json.Parser (); p.load_from_data (raw);
                var o = p.get_root ().get_object ();
                var it = new GhItem ();
                it.id = JiraStore._str (o, "id");
                it.item_type = JiraStore._str (o, "type");
                it.title = JiraStore._str (o, "title");
                it.url = JiraStore._str (o, "url");
                it.number = o.has_member ("number") ? (int) o.get_int_member ("number") : 0;
                it.state = JiraStore._str (o, "state");
                it.is_draft = o.has_member ("isDraft") && o.get_boolean_member ("isDraft");
                it.repo = JiraStore._str (o, "repo");
                it.updated = JiraStore._str (o, "updated");
                it.status_name = JiraStore._str (o, "statusName");
                return it;
            } catch (Error e) { return null; }
        }

        private static string _extract_error (string body) {
            if (body.length == 0) return "";
            try {
                var p = new Json.Parser (); p.load_from_data (body);
                var o = p.get_root ().get_object ();
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
