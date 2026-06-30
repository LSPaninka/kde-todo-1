"""jira_store.py - Jira Cloud REST v3 client (callback-based async).

Port of JiraStore.vala / the original JiraWorklogStore.qml: week worklogs,
issue picker, sprint discovery (3 strategies), subtasks, monthly totals and
worklog create / update / delete + transitions. Auth: HTTP Basic.
"""
from __future__ import annotations
import json
from urllib.parse import quote

from gi.repository import GObject

from . import util
from .util import js_str, js_int, js_obj, js_arr, js_has_num
from .models import (Worklog, Issue, Subtask, Sprint, BreakdownItem,
                     Transition, OpResult)


class JiraStore(GObject.GObject):
    __gsignals__ = {"changed": (GObject.SignalFlags.RUN_FIRST, None, ())}

    def __init__(self, cfg, http):
        super().__init__()
        self.cfg = cfg
        self.http = http
        self.worklogs: list[Worklog] = []
        self.assignable_issues: list[Issue] = []
        self.subtasks: list[Subtask] = []
        self.sprint_breakdown: list[BreakdownItem] = []
        self.my_account_id = ""
        self.current_sprint: Sprint | None = None
        self.sprint_available_sec = 0
        self.sprint_consumed_sec = 0
        self.loading = False
        self.last_error = ""
        self.last_fetched_at = 0
        self.debug_log = ""

    # ------------------------------------------------------------------
    def _have_creds(self) -> bool:
        if not self.cfg.has_jira_creds():
            self.last_error = "Faltan credenciales de Jira (sitio, email o token)."
            return False
        return True

    def _auth(self):
        from .http import Http
        return Http.basic_auth(self.cfg.jira_email, self.cfg.jira_token)

    def _site(self):
        return self.cfg.jira_site_clean

    def _get(self, url, cb):
        self._log("GET " + url)
        self.http.send("GET", url, self._auth(), None, None, cb)

    def _send(self, method, url, body, cb):
        self._log(method + " " + url)
        self.http.send(method, url, self._auth(), None, body, cb)

    def _ensure_account(self, then):
        if self.my_account_id:
            then()
            return

        def cb(code, body):
            if code == 200:
                self.my_account_id = js_str(_parse(body), "accountId")
            then()
        self._get(self._site() + "/rest/api/3/myself", cb)

    # ------------------------------------------------------------------
    # Worklogs for a week
    # ------------------------------------------------------------------
    def fetch_week(self, week_start_ms, done=None):
        if self.loading:
            return
        if not self._have_creds():
            self.emit("changed")
            return
        self.loading = True
        self.last_error = ""
        self.emit("changed")

        start = util.start_of_day_ms(week_start_ms)
        end = start + 7 * util.DAY_MS

        def do_search():
            jql = ('worklogAuthor = currentUser() AND worklogDate >= "%s" '
                   'AND worklogDate <= "%s"' % (util.fmt_jql_date(start),
                                                util.fmt_jql_date(end - 1)))
            url = (self._site() + "/rest/api/3/search/jql?jql=" + quote(jql)
                   + "&maxResults=200&fields=summary,worklog")

            def cb(code, body):
                if code != 200:
                    self.last_error = "HTTP %d al buscar worklogs." % code
                    self.loading = False
                    self.emit("changed")
                    if done:
                        done(False)
                    return
                self._process_week(body, start, end)
                if done:
                    done(True)
            self._get(url, cb)

        def after_account():
            if not self.my_account_id and self.cfg.has_jira_creds():
                # myself failed
                self.last_error = "No se pudo obtener el usuario actual."
                self.loading = False
                self.emit("changed")
                if done:
                    done(False)
                return
            do_search()
        self._ensure_account(after_account)

    def _process_week(self, body, start, end):
        root = _parse(body)
        issues = js_arr(root, "issues") or []
        out = []
        for iss in issues:
            fields = js_obj(iss, "fields") or {}
            summary = js_str(fields, "summary")
            wls = js_arr(js_obj(fields, "worklog"), "worklogs") or []
            for w in wls:
                started = util.parse_iso(js_str(w, "started"))
                if started < start or started >= end:
                    continue
                author = js_obj(w, "author") or {}
                if self.my_account_id and js_str(author, "accountId") != self.my_account_id:
                    continue
                e = Worklog()
                e.id = js_str(w, "id")
                e.issue_id = js_str(iss, "id")
                e.issue_key = js_str(iss, "key")
                e.issue_summary = summary
                e.started = started
                e.duration_sec = js_int(w, "timeSpentSeconds")
                e.comment = self._extract_adf(w.get("comment"))
                out.append(e)
        out.sort(key=lambda x: x.started)
        self.worklogs = out
        self.last_fetched_at = util.now_ms()
        self.loading = False
        self._log("Worklogs en la semana: %d" % len(out))
        self.emit("changed")

    # ------------------------------------------------------------------
    # Monthly totals (heatmap)  ->  done(ok, {day: seconds})
    # ------------------------------------------------------------------
    def fetch_month_totals(self, year, month0, done):
        if not self._have_creds():
            done(False, {})
            return

        def run():
            from datetime import datetime
            first = datetime(year, month0 + 1, 1)
            nxt = datetime(year + (month0 + 1) // 12, ((month0 + 1) % 12) + 1, 1)
            start_ms = int(first.timestamp() * 1000)
            end_ms = int(nxt.timestamp() * 1000)
            last = nxt.toordinal() - 1
            from datetime import date
            last_d = date.fromordinal(last)
            jql = ('worklogAuthor = currentUser() AND worklogDate >= "%s" '
                   'AND worklogDate <= "%s"'
                   % (util.fmt_jql_date(start_ms),
                      "%04d-%02d-%02d" % (last_d.year, last_d.month, last_d.day)))
            url = (self._site() + "/rest/api/3/search/jql?jql=" + quote(jql)
                   + "&maxResults=200&fields=worklog")

            def cb(code, body):
                if code != 200:
                    done(False, {})
                    return
                totals = {}
                issues = js_arr(_parse(body), "issues") or []
                for iss in issues:
                    wls = js_arr(js_obj(js_obj(iss, "fields"), "worklog"), "worklogs") or []
                    for w in wls:
                        sm = util.parse_iso(js_str(w, "started"))
                        if sm < start_ms or sm >= end_ms:
                            continue
                        author = js_obj(w, "author") or {}
                        if self.my_account_id and js_str(author, "accountId") != self.my_account_id:
                            continue
                        from datetime import datetime as dt
                        day = dt.fromtimestamp(sm / 1000).day
                        totals[day] = totals.get(day, 0) + js_int(w, "timeSpentSeconds")
                done(True, totals)
            self._get(url, cb)
        self._ensure_account(run)

    # ------------------------------------------------------------------
    # Issue picker
    # ------------------------------------------------------------------
    def fetch_assignable_issues(self, done):
        if not self._have_creds():
            self.emit("changed")
            done(False)
            return
        jql = (self.cfg.issue_jql.strip()
               or "assignee = currentUser() AND statusCategory != Done")
        mx = max(10, min(200, self.cfg.issue_max))
        url = (self._site() + "/rest/api/3/search/jql?jql=" + quote(jql)
               + "&maxResults=%d" % mx
               + "&fields=summary,status,issuetype,timeoriginalestimate,timeestimate,timetracking")

        def cb(code, body):
            if code != 200:
                done(False)
                return
            out = []
            for iss in (js_arr(_parse(body), "issues") or []):
                f = js_obj(iss, "fields") or {}
                it = Issue()
                it.key = js_str(iss, "key")
                it.summary = js_str(f, "summary")
                it.issuetype = js_str(js_obj(f, "issuetype"), "name")
                it.status = js_str(js_obj(f, "status"), "name")
                it.remaining_sec = self._remaining_sec(f)
                out.append(it)
            self.assignable_issues = out
            self.emit("changed")
            done(True)
        self._get(url, cb)

    # ------------------------------------------------------------------
    # Sprint info
    # ------------------------------------------------------------------
    def fetch_sprint_info(self, done=None):
        done = done or (lambda ok: None)
        if not self._have_creds():
            self._clear_sprint()
            self.emit("changed")
            done(False)
            return

        def dispatch():
            s = self.cfg.sprint_strategy
            if s == "agile-board":
                self._sprint_agile_board(done)
            elif s == "assignee-jql":
                self._sprint_assignee_jql(done)
            else:
                self._sprint_subtask_field(done)
        self._ensure_account(dispatch)

    def _sprint_subtask_field(self, done):
        field = self.cfg.sprint_field or "customfield_10020"
        jql = "issuetype in subTaskIssueTypes() AND assignee = currentUser()"
        url = (self._site() + "/rest/api/3/search/jql?jql=" + quote(jql)
               + "&maxResults=200&fields=summary,worklog,timeoriginalestimate,"
               + "timeestimate,timetracking," + quote(field))

        def cb(code, body):
            if code != 200:
                self._clear_sprint(); self.emit("changed"); done(False); return
            issues = js_arr(_parse(body), "issues") or []
            if not issues:
                self._clear_sprint(); self.emit("changed"); done(True); return
            active = self._find_active_sprint(issues, field)
            if not active:
                self._clear_sprint(); self.emit("changed"); done(True); return
            self._set_active_sprint(active)
            self._compute_sprint_totals(issues, active, field)
            self.emit("changed"); done(True)
        self._get(url, cb)

    def _sprint_agile_board(self, done):
        board = self.cfg.sprint_board_id
        if board <= 0:
            self.last_error = "Board ID no configurado."
            self._clear_sprint(); self.emit("changed"); done(False); return

        def cb(code, body):
            if code != 200:
                self._clear_sprint(); self.emit("changed"); done(False); return
            values = js_arr(_parse(body), "values") or []
            if not values:
                self._clear_sprint(); self.emit("changed"); done(True); return
            active = values[0]
            self._set_active_sprint(active)
            jql = "sprint = %s AND assignee = currentUser()" % js_str(active, "id")
            url2 = (self._site() + "/rest/api/3/search/jql?jql=" + quote(jql)
                    + "&maxResults=200&fields=summary,worklog,timeoriginalestimate,"
                    + "timeestimate,timetracking")

            def cb2(c2, b2):
                if c2 == 200:
                    issues = js_arr(_parse(b2), "issues") or []
                    self._compute_sprint_totals(issues, active, None)
                self.emit("changed"); done(True)
            self._get(url2, cb2)
        self._get(self._site() + "/rest/agile/1.0/board/%d/sprint?state=active" % board, cb)

    def _sprint_assignee_jql(self, done):
        field = self.cfg.sprint_field or "customfield_10020"
        jql = "sprint in openSprints() AND assignee = currentUser()"
        url = (self._site() + "/rest/api/3/search/jql?jql=" + quote(jql)
               + "&maxResults=200&fields=summary,worklog,timeoriginalestimate,"
               + "timeestimate,timetracking," + quote(field))

        def cb(code, body):
            if code != 200:
                self._clear_sprint(); self.emit("changed"); done(False); return
            issues = js_arr(_parse(body), "issues") or []
            if not issues:
                self._clear_sprint(); self.emit("changed"); done(True); return
            active = self._find_active_sprint(issues, field)
            if not active:
                self._clear_sprint(); self.emit("changed"); done(True); return
            self._set_active_sprint(active)
            self._compute_sprint_totals(issues, active, field)
            self.emit("changed"); done(True)
        self._get(url, cb)

    def _find_active_sprint(self, issues, field):
        for iss in issues:
            arr = js_arr(js_obj(iss, "fields"), field) or []
            for s in arr:
                if isinstance(s, dict) and str(s.get("state", "")).lower() == "active":
                    return s
        return None

    def _set_active_sprint(self, s):
        sp = Sprint()
        sp.id = js_int(s, "id")
        sp.name = js_str(s, "name")
        sp.start_ms = util.parse_iso(js_str(s, "startDate"))
        sp.end_ms = util.parse_iso(js_str(s, "endDate"))
        self.current_sprint = sp

    def _clear_sprint(self):
        self.current_sprint = None
        self.sprint_available_sec = 0
        self.sprint_consumed_sec = 0
        self.sprint_breakdown = []

    def _compute_sprint_totals(self, issues, active, field):
        s_start = util.parse_iso(js_str(active, "startDate"))
        s_end = util.parse_iso(js_str(active, "endDate"))
        active_id = js_int(active, "id")
        available = consumed = 0
        breakdown = []
        for iss in issues:
            f = js_obj(iss, "fields") or {}
            if field is not None:
                arr = js_arr(f, field) or []
                if not any(isinstance(x, dict) and js_int(x, "id") == active_id for x in arr):
                    continue
            rem = self._remaining_sec(f)
            available += rem
            if rem > 0:
                bi = BreakdownItem()
                bi.key = js_str(iss, "key")
                bi.summary = js_str(f, "summary")
                bi.remaining_sec = rem
                breakdown.append(bi)
            for w in (js_arr(js_obj(f, "worklog"), "worklogs") or []):
                sm = util.parse_iso(js_str(w, "started"))
                if sm < s_start or sm > s_end:
                    continue
                author = js_obj(w, "author") or {}
                if self.my_account_id and js_str(author, "accountId") != self.my_account_id:
                    continue
                consumed += js_int(w, "timeSpentSeconds")
        breakdown.sort(key=lambda b: -b.remaining_sec)
        self.sprint_available_sec = available
        self.sprint_consumed_sec = consumed
        self.sprint_breakdown = breakdown

    # ------------------------------------------------------------------
    # Subtasks
    # ------------------------------------------------------------------
    def fetch_subtasks(self, done=None):
        done = done or (lambda ok: None)
        if not self._have_creds():
            self.emit("changed")
            done(False)
            return
        jql = (self.cfg.subtask_jql.strip()
               or "issuetype in subTaskIssueTypes() AND assignee = currentUser() "
                  "AND statusCategory != Done ORDER BY updated DESC")
        url = (self._site() + "/rest/api/3/search/jql?jql=" + quote(jql)
               + "&maxResults=100&fields=summary,status,parent,timeoriginalestimate,"
               + "timeestimate,timetracking")

        def cb(code, body):
            if code != 200:
                done(False)
                return
            out = []
            for iss in (js_arr(_parse(body), "issues") or []):
                f = js_obj(iss, "fields") or {}
                st = js_obj(f, "status") or {}
                sc = js_obj(st, "statusCategory") or {}
                parent = js_obj(f, "parent")
                s = Subtask()
                s.key = js_str(iss, "key")
                s.summary = js_str(f, "summary")
                s.status = js_str(st, "name")
                s.status_category = js_str(sc, "key")
                s.status_color = js_str(sc, "colorName")
                s.remaining_sec = self._remaining_sec(f)
                s.parent_key = js_str(parent, "key") if parent else ""
                s.parent_summary = js_str(js_obj(parent, "fields"), "summary") if parent else ""
                out.append(s)
            self.subtasks = out
            self.emit("changed")
            done(True)
        self._get(url, cb)

    def fetch_transitions(self, issue_key, done):
        if not self._have_creds():
            done([])
            return

        def cb(code, body):
            if code != 200:
                done([])
                return
            out = []
            for t in (js_arr(_parse(body), "transitions") or []):
                to = js_obj(t, "to") or {}
                tr = Transition()
                tr.id = js_str(t, "id")
                tr.name = js_str(t, "name")
                tr.to_status = js_str(to, "name")
                tr.to_status_color = js_str(js_obj(to, "statusCategory"), "colorName")
                out.append(tr)
            done(out)
        self._get(self._site() + "/rest/api/3/issue/" + quote(issue_key) + "/transitions", cb)

    def transition_issue(self, issue_key, transition_id, done):
        if not self._have_creds():
            done(OpResult(False, "no-creds"))
            return
        body = json.dumps({"transition": {"id": str(transition_id)}})

        def cb(code, resp):
            if code in (200, 204):
                done(OpResult(True))
            else:
                done(OpResult(False, "HTTP %d: %s" % (code, self._extract_error(resp))))
        self._send("POST", self._site() + "/rest/api/3/issue/" + quote(issue_key) + "/transitions", body, cb)

    def issue_web_url(self, issue_key) -> str:
        if not self.cfg.has_jira_creds() or not issue_key:
            return ""
        return self._site() + "/browse/" + quote(issue_key)

    # ------------------------------------------------------------------
    # Create / Update / Delete
    # ------------------------------------------------------------------
    def create_worklog(self, issue_key, started_ms, duration_sec, comment, done):
        if not self._have_creds():
            done(OpResult(False, self.last_error))
            return
        body = {"started": util.fmt_jira_started(started_ms), "timeSpentSeconds": int(duration_sec)}
        if comment:
            body["comment"] = self._comment_adf(comment)

        def cb(code, resp):
            if 200 <= code < 300:
                done(OpResult(True))
            else:
                done(OpResult(False, "HTTP %d: %s" % (code, self._extract_error(resp))))
        self._send("POST", self._site() + "/rest/api/3/issue/" + quote(issue_key) + "/worklog",
                   json.dumps(body), cb)

    def update_worklog(self, issue_key, worklog_id, started_ms, duration_sec, comment, done):
        if not self._have_creds():
            done(OpResult(False, self.last_error))
            return
        body = {"started": util.fmt_jira_started(started_ms), "timeSpentSeconds": int(duration_sec)}
        if comment is not None:
            body["comment"] = self._comment_adf(comment)

        def cb(code, resp):
            if code == 200:
                done(OpResult(True))
            else:
                done(OpResult(False, "HTTP %d: %s" % (code, self._extract_error(resp))))
        self._send("PUT", self._site() + "/rest/api/3/issue/" + quote(issue_key)
                   + "/worklog/" + quote(worklog_id), json.dumps(body), cb)

    def delete_worklog(self, issue_key, worklog_id, done):
        if not self._have_creds():
            done(OpResult(False, self.last_error))
            return

        def cb(code, resp):
            if code in (200, 204):
                done(OpResult(True))
            else:
                done(OpResult(False, "HTTP %d: %s" % (code, self._extract_error(resp))))
        self._send("DELETE", self._site() + "/rest/api/3/issue/" + quote(issue_key)
                   + "/worklog/" + quote(worklog_id), None, cb)

    # ------------------------------------------------------------------
    def _remaining_sec(self, f) -> int:
        if not f:
            return 0
        mode = self.cfg.remaining_mode
        tt = js_obj(f, "timetracking")
        if mode == "calculated":
            if js_has_num(f, "timeoriginalestimate"):
                orig = js_int(f, "timeoriginalestimate")
            elif tt and js_has_num(tt, "originalEstimateSeconds"):
                orig = js_int(tt, "originalEstimateSeconds")
            else:
                orig = 0
            spent = js_int(tt, "timeSpentSeconds") if (tt and js_has_num(tt, "timeSpentSeconds")) else 0
            return max(0, orig - spent)
        if tt and js_has_num(tt, "remainingEstimateSeconds"):
            return js_int(tt, "remainingEstimateSeconds")
        if js_has_num(f, "timeestimate"):
            return js_int(f, "timeestimate")
        return 0

    def _comment_adf(self, text):
        return {"type": "doc", "version": 1,
                "content": [{"type": "paragraph",
                             "content": [{"type": "text", "text": text}]}]}

    def _extract_adf(self, node) -> str:
        if node is None:
            return ""
        if isinstance(node, str):
            return node
        if not isinstance(node, dict):
            return ""
        t = node.get("type")
        if t == "text":
            return node.get("text", "") or ""
        parts = "".join(self._extract_adf(c) for c in (node.get("content") or []))
        if t == "paragraph":
            parts += "\n"
        return parts

    def _extract_error(self, body) -> str:
        if not body:
            return ""
        try:
            d = json.loads(body)
            if isinstance(d, dict):
                ems = d.get("errorMessages")
                if isinstance(ems, list) and ems:
                    return "; ".join(str(x) for x in ems)
                if d.get("errors"):
                    return "; ".join(f"{k}: {v}" for k, v in d["errors"].items())
                if d.get("message"):
                    return str(d["message"])
        except (ValueError, TypeError):
            pass
        return body[:240]

    def _log(self, msg):
        self.debug_log += msg + "\n"
        if len(self.debug_log) > 80000:
            self.debug_log = self.debug_log[-40000:]
        if self.cfg.debug:
            print("[JiraWorklog]", msg)


def _parse(body):
    try:
        v = json.loads(body)
        return v if isinstance(v, dict) else None
    except (ValueError, TypeError):
        return None
