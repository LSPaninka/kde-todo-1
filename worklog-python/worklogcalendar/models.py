"""models.py - plain data carriers used by the stores and the UI.

started: Unix epoch milliseconds. duration_sec: seconds. Worklog and
ClockifyEntry share the (started, duration_sec) shape so the calendar grid can
render both with the same code.
"""
from __future__ import annotations
from dataclasses import dataclass, field


@dataclass
class Worklog:
    id: str = ""
    issue_id: str = ""
    issue_key: str = ""
    issue_summary: str = ""
    started: int = 0
    duration_sec: int = 0
    comment: str = ""


@dataclass
class ClockifyEntry:
    id: str = ""
    started: int = 0
    duration_sec: int = 0
    description: str = ""
    project_id: str = ""
    project_name: str = ""
    project_color: str = ""
    tag_ids: list = field(default_factory=list)
    tag_names: list = field(default_factory=list)
    billable: bool = False


@dataclass
class Project:
    id: str = ""
    name: str = ""
    color: str = ""
    billable: bool = False


@dataclass
class Tag:
    id: str = ""
    name: str = ""


@dataclass
class Issue:
    key: str = ""
    summary: str = ""
    issuetype: str = ""
    status: str = ""
    remaining_sec: int = 0


@dataclass
class Subtask:
    key: str = ""
    summary: str = ""
    status: str = ""
    status_category: str = ""
    status_color: str = ""
    remaining_sec: int = 0
    parent_key: str = ""
    parent_summary: str = ""


@dataclass
class Sprint:
    id: int = 0
    name: str = ""
    start_ms: int = 0
    end_ms: int = 0


@dataclass
class BreakdownItem:
    key: str = ""
    summary: str = ""
    remaining_sec: int = 0


@dataclass
class Transition:
    id: str = ""
    name: str = ""
    to_status: str = ""
    to_status_color: str = ""


@dataclass
class OpResult:
    ok: bool = False
    err: str = ""
