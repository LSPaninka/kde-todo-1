/*
 * TaskEditDialog.vala — create or edit a task (title, description, category,
 * priority) and manage its subtasks inline. Commits through TaskStore.
 */

namespace Ct {

    public class TaskEditDialog : Adw.Dialog {
        private TaskStore store;
        private Config config;
        private int64 editing_id = 0;   // 0 = new task

        private Adw.EntryRow title_row;
        private Gtk.TextView desc_view;
        private Adw.ComboRow _prio_row;
        private Adw.ComboRow cat_row;
        private Gtk.ListBox sub_list;

        public TaskEditDialog (TaskStore store, Config config) {
            this.store = store;
            this.config = config;
            build_ui ();
        }

        public void load_new (int category) {
            editing_id = 0;
            title = "Nueva tarea";
            title_row.text = "";
            desc_view.buffer.text = "";
            _prio_row.selected = _prio_index ("M");
            cat_row.selected = (uint) int.max (0, int.min (config.category_count - 1, category));
            _clear_subs ();
        }

        public void load_edit (Task t) {
            editing_id = t.id;
            title = "Editar tarea";
            title_row.text = t.title;
            desc_view.buffer.text = t.description;
            _prio_row.selected = _prio_index (t.priority);
            cat_row.selected = (uint) int.max (0, int.min (config.category_count - 1, t.category));
            _clear_subs ();
            foreach (var s in t.subtasks)
                _add_sub_row (s.id, s.title, s.priority, s.done);
        }

        private void build_ui () {
            content_width = 520;
            content_height = 620;

            var tv = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = false;
            header.show_start_title_buttons = false;

            var cancel = new Gtk.Button.with_label ("Cancelar");
            cancel.clicked.connect (() => close ());
            header.pack_start (cancel);

            var save = new Gtk.Button.with_label ("Guardar");
            save.add_css_class ("suggested-action");
            save.clicked.connect (on_save);
            header.pack_end (save);
            tv.add_top_bar (header);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.vexpand = true;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_top = 12, margin_bottom = 12, margin_start = 12, margin_end = 12
            };

            var g1 = new Adw.PreferencesGroup ();
            title_row = new Adw.EntryRow () { title = "Título" };
            g1.add (title_row);

            _prio_row = new Adw.ComboRow () { title = "Prioridad" };
            _prio_row.model = new Gtk.StringList (PRIORITIES);
            g1.add (_prio_row);

            var cat_names = new string[config.category_count];
            for (int i = 0; i < config.category_count; i++) cat_names[i] = config.category_name (i);
            cat_row = new Adw.ComboRow () { title = "Categoría" };
            cat_row.model = new Gtk.StringList (cat_names);
            g1.add (cat_row);
            box.append (g1);

            var desc_group = new Adw.PreferencesGroup () { title = "Descripción" };
            var frame = new Gtk.Frame (null);
            desc_view = new Gtk.TextView () {
                wrap_mode = Gtk.WrapMode.WORD_CHAR,
                top_margin = 6, bottom_margin = 6, left_margin = 6, right_margin = 6,
                height_request = 90
            };
            frame.child = desc_view;
            desc_group.add (frame);
            box.append (desc_group);

            var sub_group = new Adw.PreferencesGroup () { title = "Subtareas" };
            var add_sub = new Gtk.Button () { icon_name = "list-add-symbolic" };
            add_sub.add_css_class ("flat");
            add_sub.tooltip_text = "Añadir subtarea";
            add_sub.clicked.connect (() => _add_sub_row (0, "", "M", false));
            sub_group.header_suffix = add_sub;
            sub_list = new Gtk.ListBox ();
            sub_list.add_css_class ("boxed-list");
            sub_list.selection_mode = Gtk.SelectionMode.NONE;
            var sub_placeholder = new Gtk.Label ("Sin subtareas") { margin_top = 8, margin_bottom = 8 };
            sub_placeholder.add_css_class ("dim");
            sub_list.set_placeholder (sub_placeholder);
            sub_group.add (sub_list);
            box.append (sub_group);

            scroll.child = box;
            tv.content = scroll;
            set_child (tv);
        }

        private Gee.ArrayList<SubRow> _sub_rows = new Gee.ArrayList<SubRow> ();

        private class SubRow {
            public int64 id;
            public Gtk.CheckButton done;
            public Gtk.Entry entry;
            public Gtk.DropDown prio;
            public Gtk.ListBoxRow row;
        }

        private void _clear_subs () {
            foreach (var sr in _sub_rows) sub_list.remove (sr.row);
            _sub_rows.clear ();
        }

        private void _add_sub_row (int64 id, string title_txt, string priority, bool done) {
            var sr = new SubRow ();
            sr.id = id;
            var hb = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_top = 4, margin_bottom = 4, margin_start = 6, margin_end = 6
            };
            sr.done = new Gtk.CheckButton () { active = done, valign = Gtk.Align.CENTER };
            sr.entry = new Gtk.Entry () { text = title_txt, hexpand = true, placeholder_text = "Subtarea" };
            sr.prio = new Gtk.DropDown.from_strings (PRIORITIES) { valign = Gtk.Align.CENTER };
            sr.prio.selected = _prio_index (priority);
            var del = new Gtk.Button () { icon_name = "user-trash-symbolic", valign = Gtk.Align.CENTER };
            del.add_css_class ("flat");
            hb.append (sr.done);
            hb.append (sr.entry);
            hb.append (sr.prio);
            hb.append (del);
            var row = new Gtk.ListBoxRow () { child = hb, activatable = false };
            sr.row = row;
            del.clicked.connect (() => {
                sub_list.remove (row);
                _sub_rows.remove (sr);
            });
            _sub_rows.add (sr);
            sub_list.append (row);
        }

        private void on_save () {
            string t = title_row.text.strip ();
            if (t.length == 0) { title_row.grab_focus (); return; }
            string desc = desc_view.buffer.text;
            string prio = PRIORITIES[_prio_row.selected];
            int category = (int) cat_row.selected;

            int64 id = editing_id;
            if (id == 0) {
                id = store.add_task (t, category, prio, desc);
            } else {
                store.update_task (id, t, desc, category, prio);
            }

            var subs = new Gee.ArrayList<Subtask> ();
            foreach (var sr in _sub_rows) {
                string st = sr.entry.text.strip ();
                if (st.length == 0) continue;
                subs.add (new Subtask.with (sr.id, st, PRIORITIES[sr.prio.selected], sr.done.active));
            }
            store.replace_subtasks (id, subs);
            close ();
        }

        private uint _prio_index (string p) {
            for (uint i = 0; i < PRIORITIES.length; i++)
                if (PRIORITIES[i] == p) return i;
            return 2; // M
        }
    }
}
