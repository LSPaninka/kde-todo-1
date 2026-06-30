"""clockify_store.py - Clockify REST v1 client (callback-based async).

Port of ClockifyStore.vala. Resolves user + workspace via /user (cached into
Config), loads projects + tags, fetches the week's entries, supports CRUD and a
Jira -> Clockify sync. Auth: X-Api-Key header.
"""
from __future__ import annotations
import json
import re
from datetime import datetime, timezone
from urllib.parse import quote

from gi.repository import GObject

from . import util
from .util import js_str, js_int, js_obj, js_bool
from .models import Project, Tag, ClockifyEntry, OpResult

BASE = "https://api.clockify.me/api/v1"
_OID = re.compile(r"^[0-9a-fA-F]{24}$")


class ClockifyStore(GObject.GObject):
    __gsignals__ = {"changed": (GObject.SignalFlags.RUN_FIRST, None, ())}

    def __init__(self, cfg, http):
        super().__init__()
        self.cfg = cfg
        self.http = http
        self.workspace_id = cfg.clockify_workspace_id if _valid(cfg.clockify_workspace_id) else ""
        self.user_id = cfg.clockify_user_id if _valid(cfg.clockify_user_id) else ""
        self.projects: list[Project] = []
        self.tags: list[Tag] = []
        self.entries: list[ClockifyEntry] = []
        self.loading = False
        self.last_error = ""
        self.last_fetched_at = 0
        self.debug_log = ""

    def _api_key(self):
        return self.cfg.clockify_api_key

    def ready(self):
        return bool(self._api_key())

    def _req(self, method, url, body, cb):
        self._log(method + " " + url)
        self.http.send(method, url, None, self._api_key(), body, cb)

    # ------------------------------------------------------------------
    def ensure_context(self, done):
        """done(ok: bool)"""
        if not self.ready():
            self.last_error = "Falta la API key de Clockify."
            self.emit("changed")
            done(False)
            return
        if _valid(self.cfg.clockify_workspace_id):
            self.workspace_id = self.cfg.clockify_workspace_id
        if _valid(self.cfg.clockify_user_id):
            self.user_id = self.cfg.clockify_user_id
        if _valid(self.workspace_id) and _valid(self.user_id) and self.projects:
            done(True)
            return

        def cb(code, body):
            if code != 200:
                self.last_error = "HTTP %d contra /user." % code
                self.emit("changed")
                done(False)
                return
            obj = _parse(body) or {}
            self.user_id = js_str(obj, "id")
            if not _valid(self.workspace_id):
                self.workspace_id = js_str(obj, "defaultWorkspace") or js_str(obj, "activeWorkspace")
            self.cfg.clockify_user_id = self.user_id
            self.cfg.clockify_workspace_id = self.workspace_id
            if not _valid(self.workspace_id):
                self.last_error = "No pude resolver un workspace válido."
                self.emit("changed")
                done(False)
                return
            self._load_projects(lambda: self._load_tags(lambda: done(True)))
        self._req("GET", BASE + "/user", None, cb)

    def _load_projects(self, then):
        def cb(code, body):
            out = []
            if code == 200:
                for p in (_parse_arr(body) or []):
                    pr = Project()
                    pr.id = js_str(p, "id")
                    pr.name = js_str(p, "name")
                    pr.color = js_str(p, "color")
                    pr.billable = js_bool(p, "billable")
                    out.append(pr)
            self.projects = out
            self._log("Proyectos: %d" % len(out))
            then()
        self._req("GET", BASE + "/workspaces/" + self.workspace_id
                  + "/projects?archived=false&page-size=200", None, cb)

    def _load_tags(self, then):
        def cb(code, body):
            out = []
            if code == 200:
                for t in (_parse_arr(body) or []):
                    tg = Tag()
                    tg.id = js_str(t, "id")
                    tg.name = js_str(t, "name")
                    out.append(tg)
            self.tags = out
            then()
        self._req("GET", BASE + "/workspaces/" + self.workspace_id
                  + "/tags?archived=false&page-size=200", None, cb)

    # ------------------------------------------------------------------
    def fetch_week(self, week_start_ms, done=None):
        if self.loading:
            return
        self.loading = True
        self.last_error = ""
        self.emit("changed")

        def after(ok):
            if not ok:
                self.loading = False
                self.emit("changed")
                if done:
                    done(False)
                return
            start = util.start_of_day_ms(week_start_ms)
            end = start + 7 * util.DAY_MS
            url = (BASE + "/workspaces/" + self.workspace_id + "/user/" + self.user_id
                   + "/time-entries?start=" + quote(util.fmt_utc_iso(start))
                   + "&end=" + quote(util.fmt_utc_iso(end)) + "&page-size=200")

            def cb(code, body):
                if code != 200:
                    self.last_error = "HTTP %d al traer time entries." % code
                    self.loading = False
                    self.emit("changed")
                    if done:
                        done(False)
                    return
                self.entries = self._parse_entries(body)
                self.last_fetched_at = util.now_ms()
                self.loading = False
                self._log("Entries: %d" % len(self.entries))
                self.emit("changed")
                if done:
                    done(True)
            self._req("GET", url, None, cb)
        self.ensure_context(after)

    def _parse_entries(self, body):
        out = []
        for e in (_parse_arr(body) or []):
            ti = js_obj(e, "timeInterval") or {}
            s, en = js_str(ti, "start"), js_str(ti, "end")
            if not s or not en:
                continue
            sm, em = util.parse_iso(s), util.parse_iso(en)
            if sm == 0 or em <= sm:
                continue
            ce = ClockifyEntry()
            ce.id = js_str(e, "id")
            ce.started = sm
            ce.duration_sec = int((em - sm) / 1000)
            ce.description = js_str(e, "description")
            ce.project_id = js_str(e, "projectId")
            p = self._project_by_id(ce.project_id)
            ce.project_name = p.name if p else ""
            ce.project_color = p.color if p else ""
            ce.billable = js_bool(e, "billable")
            tids = e.get("tagIds") or []
            ce.tag_ids = [t for t in tids if isinstance(t, str)]
            ce.tag_names = [self._tag_by_id(t).name for t in ce.tag_ids if self._tag_by_id(t)]
            out.append(ce)
        out.sort(key=lambda x: x.started)
        return out

    def fetch_month_totals(self, year, month0, done):
        def after(ok):
            if not ok:
                done(False, {})
                return
            first = datetime(year, month0 + 1, 1)
            nxt = datetime(year + (month0 + 1) // 12, ((month0 + 1) % 12) + 1, 1)
            totals = {}
            page = [1]
            page_size = 200

            def fetch_page():
                url = (BASE + "/workspaces/" + self.workspace_id + "/user/" + self.user_id
                       + "/time-entries?start=" + quote(util.fmt_utc_iso(int(first.timestamp() * 1000)))
                       + "&end=" + quote(util.fmt_utc_iso(int(nxt.timestamp() * 1000)))
                       + "&page-size=%d&page=%d" % (page_size, page[0]))

                def cb(code, body):
                    if code != 200:
                        done(True, totals)
                        return
                    arr = _parse_arr(body) or []
                    for e in arr:
                        ti = js_obj(e, "timeInterval") or {}
                        sm, em = util.parse_iso(js_str(ti, "start")), util.parse_iso(js_str(ti, "end"))
                        if sm == 0 or em <= sm:
                            continue
                        d = datetime.fromtimestamp(sm / 1000)
                        if d.year == year and d.month == month0 + 1:
                            totals[d.day] = totals.get(d.day, 0) + int((em - sm) / 1000)
                    if len(arr) >= page_size:
                        page[0] += 1
                        fetch_page()
                    else:
                        done(True, totals)
                self._req("GET", url, None, cb)
            fetch_page()
        self.ensure_context(after)

    def _project_by_id(self, pid):
        return next((p for p in self.projects if p.id == pid), None) if pid else None

    def _tag_by_id(self, tid):
        return next((t for t in self.tags if t.id == tid), None)

    # ------------------------------------------------------------------
    def create_entry(self, start_ms, end_ms, description, project_id, tag_ids, billable, done):
        if not self._context_ready():
            done(OpResult(False, self.last_error))
            return
        body = {"start": util.fmt_utc_iso(start_ms), "end": util.fmt_utc_iso(end_ms),
                "description": description or "", "billable": bool(billable)}
        if project_id:
            body["projectId"] = project_id
        if tag_ids:
            body["tagIds"] = list(tag_ids)
        self._mutate("POST", BASE + "/workspaces/" + self.workspace_id + "/time-entries",
                     json.dumps(body), done)

    def update_entry(self, entry_id, start_ms, end_ms, description, project_id, tag_ids, billable, done):
        if not self._context_ready():
            done(OpResult(False, self.last_error))
            return
        body = {"start": util.fmt_utc_iso(start_ms), "end": util.fmt_utc_iso(end_ms),
                "description": description or "", "billable": bool(billable),
                "tagIds": list(tag_ids or [])}
        if project_id:
            body["projectId"] = project_id
        self._mutate("PUT", BASE + "/workspaces/" + self.workspace_id
                     + "/time-entries/" + quote(entry_id), json.dumps(body), done)

    def delete_entry(self, entry_id, done):
        if not self._context_ready():
            done(OpResult(False, self.last_error))
            return

        def cb(code, resp):
            if code in (200, 204):
                done(OpResult(True))
            else:
                done(OpResult(False, "HTTP %d: %s" % (code, self._extract_error(resp))))
        self._req("DELETE", BASE + "/workspaces/" + self.workspace_id
                  + "/time-entries/" + quote(entry_id), None, cb)

    def _mutate(self, method, url, body, done):
        def cb(code, resp):
            if 200 <= code < 300:
                done(OpResult(True))
            else:
                done(OpResult(False, "HTTP %d: %s" % (code, self._extract_error(resp))))
        self._req(method, url, body, cb)

    def _context_ready(self):
        if not _valid(self.workspace_id) or not _valid(self.user_id):
            self.last_error = "Sincronizá primero (workspace/usuario no resueltos)."
            return False
        return True

    # ------------------------------------------------------------------
    # Sync from Jira -> done([created, skipped, failed])
    # ------------------------------------------------------------------
    def sync_from_jira(self, jira_worklogs, default_project_id, default_billable, done):
        if not jira_worklogs:
            done([0, 0, 0])
            return

        def after(ok):
            if not ok:
                done([0, 0, 0])
                return
            to_create, skipped = [], 0
            for j in jira_worklogs:
                desc = j.issue_key + (": " + j.issue_summary if j.issue_summary else "")
                js, je = j.started, j.started + j.duration_sec * 1000
                hit = False
                for c in self.entries:
                    if c.description != desc:
                        continue
                    cs, ce = c.started, c.started + c.duration_sec * 1000
                    if js < ce and cs < je:
                        hit = True
                        break
                if hit:
                    skipped += 1
                else:
                    to_create.append(j)
            counters = {"created": 0, "failed": 0}

            def step(i):
                if i >= len(to_create):
                    done([counters["created"], skipped, counters["failed"]])
                    return
                j = to_create[i]
                desc = j.issue_key + (": " + j.issue_summary if j.issue_summary else "")
                je = j.started + j.duration_sec * 1000

                def after_create(res):
                    if res.ok:
                        counters["created"] += 1
                    else:
                        counters["failed"] += 1
                    step(i + 1)
                self.create_entry(j.started, je, desc, default_project_id, [], default_billable, after_create)
            step(0)
        self.ensure_context(after)

    # ------------------------------------------------------------------
    def _extract_error(self, body):
        try:
            d = json.loads(body)
            if isinstance(d, dict) and d.get("message"):
                return str(d["message"])
        except (ValueError, TypeError):
            pass
        return (body or "")[:240]

    def _log(self, msg):
        self.debug_log += msg + "\n"
        if len(self.debug_log) > 80000:
            self.debug_log = self.debug_log[-40000:]
        if self.cfg.debug:
            print("[Clockify]", msg)


def _valid(s):
    return bool(s) and bool(_OID.match(s))


def _parse(body):
    try:
        v = json.loads(body)
        return v if isinstance(v, dict) else None
    except (ValueError, TypeError):
        return None


def _parse_arr(body):
    try:
        v = json.loads(body)
        return v if isinstance(v, list) else None
    except (ValueError, TypeError):
        return None
