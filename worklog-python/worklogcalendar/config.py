"""config.py - thin wrapper over the GSettings schema."""
from __future__ import annotations
from gi.repository import Gio

from . import APP_ID


class Config:
    def __init__(self):
        self.settings = Gio.Settings.new(APP_ID)

    # ---- Jira ----
    @property
    def jira_site_clean(self) -> str:
        return self.settings.get_string("jira-site").strip().rstrip("/")

    @property
    def jira_email(self) -> str:
        return self.settings.get_string("jira-email").strip()

    @property
    def jira_token(self) -> str:
        return self.settings.get_string("jira-token").strip()

    def has_jira_creds(self) -> bool:
        return bool(self.jira_site_clean and self.jira_email and self.jira_token)

    # ---- Clockify ----
    @property
    def clockify_api_key(self) -> str:
        return self.settings.get_string("clockify-api-key").strip()

    @property
    def clockify_workspace_id(self) -> str:
        return self.settings.get_string("clockify-workspace-id").strip()

    @clockify_workspace_id.setter
    def clockify_workspace_id(self, v: str):
        self.settings.set_string("clockify-workspace-id", v)

    @property
    def clockify_user_id(self) -> str:
        return self.settings.get_string("clockify-user-id").strip()

    @clockify_user_id.setter
    def clockify_user_id(self, v: str):
        self.settings.set_string("clockify-user-id", v)

    @property
    def clockify_default_project_id(self) -> str:
        return self.settings.get_string("clockify-default-project-id").strip()

    @clockify_default_project_id.setter
    def clockify_default_project_id(self, v: str):
        self.settings.set_string("clockify-default-project-id", v)

    @property
    def clockify_billable_default(self) -> bool:
        return self.settings.get_boolean("clockify-billable-default")

    # ---- view / behaviour ----
    @property
    def source(self) -> str:
        return self.settings.get_string("worklog-source")

    @source.setter
    def source(self, v: str):
        self.settings.set_string("worklog-source", v)

    @property
    def view_mode(self) -> str:
        return self.settings.get_string("view-mode")

    @view_mode.setter
    def view_mode(self, v: str):
        self.settings.set_string("view-mode", v)

    @property
    def daily_target_hours(self) -> float:
        return self.settings.get_double("daily-target-hours")

    @property
    def show_issue_summary(self) -> bool:
        return self.settings.get_boolean("show-issue-summary")

    @property
    def issue_jql(self) -> str:
        return self.settings.get_string("issue-jql")

    @property
    def issue_max(self) -> int:
        return self.settings.get_int("issue-max")

    @property
    def show_bottom_panel(self) -> bool:
        return self.settings.get_boolean("show-bottom-panel")

    @property
    def bottom_view(self) -> str:
        return self.settings.get_string("bottom-view")

    @bottom_view.setter
    def bottom_view(self, v: str):
        self.settings.set_string("bottom-view", v)

    @property
    def show_subtask_table(self) -> bool:
        return self.settings.get_boolean("show-subtask-table")

    @property
    def subtask_jql(self) -> str:
        return self.settings.get_string("subtask-jql")

    @property
    def subtask_show_parent(self) -> bool:
        return self.settings.get_boolean("subtask-show-parent")

    @property
    def sprint_strategy(self) -> str:
        return self.settings.get_string("sprint-strategy")

    @property
    def sprint_field(self) -> str:
        return self.settings.get_string("sprint-field")

    @property
    def sprint_board_id(self) -> int:
        return self.settings.get_int("sprint-board-id")

    @property
    def remaining_mode(self) -> str:
        return self.settings.get_string("remaining-mode")

    @property
    def run_in_background(self) -> bool:
        return self.settings.get_boolean("run-in-background")

    @property
    def show_tray_icon(self) -> bool:
        return self.settings.get_boolean("show-tray-icon")

    @property
    def debug(self) -> bool:
        return self.settings.get_boolean("debug")
