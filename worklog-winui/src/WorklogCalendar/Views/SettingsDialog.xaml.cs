using Microsoft.UI.Xaml.Controls;
using WorklogCalendar.Services;

namespace WorklogCalendar.Views;

public sealed partial class SettingsDialog : ContentDialog
{
    private readonly AppSettings _s;

    public SettingsDialog(AppSettings s)
    {
        this.InitializeComponent();
        _s = s;

        ViewModeChooser.SelectedIndex = _s.ViewMode == "24h" ? 1 : 0;
        SourceChooser.SelectedIndex = _s.Source switch
        {
            "clockify" => 2,
            "jira-clockify" => 1,
            _ => 0
        };
        FirstDayChooser.SelectedIndex = _s.FirstDayOfWeek == 1 ? 1 : 0;
        DailyTarget.Value = _s.DailyTargetHours;
        WinWidth.Value = _s.WindowWidth;
        WinHeight.Value = _s.WindowHeight;
        AlwaysOnTop.IsChecked = _s.AlwaysOnTop;
        ModalW.Value = _s.ModalWidth;
        ModalH.Value = _s.ModalHeight;

        ShowGauges.IsChecked = _s.ShowSprintGauges;
        ShowRingsView.IsChecked = _s.ShowRingsView;
        ShowSubtaskTable.IsChecked = _s.ShowSubtaskTable;
        SubtaskShowParent.IsChecked = _s.SubtaskShowParent;
        SubtaskJql.Text = _s.SubtaskJql;
        SprintStrategyChooser.SelectedIndex = _s.SprintStrategy switch
        {
            "agile-board" => 1,
            "assignee-jql" => 2,
            _ => 0
        };
        SprintField.Text = _s.SprintField;
        SprintBoardId.Value = _s.SprintBoardId;
        RemainingChooser.SelectedIndex = _s.RemainingMode == "calculated" ? 1 : 0;

        JiraSite.Text = _s.JiraSite;
        JiraEmail.Text = _s.JiraEmail;
        JiraToken.Password = _s.JiraToken;
        JiraJql.Text = _s.JiraIssueJql;
        JiraIssueMax.Value = _s.JiraIssueMax;
        JiraShowSummary.IsChecked = _s.ShowJiraSummary;
        JiraDebug.IsChecked = _s.JiraDebug;

        ClockifyKey.Password = _s.ClockifyApiKey;
        ClockifyWorkspace.Text = _s.ClockifyWorkspaceId;
        ClockifyDefaultProject.Text = _s.ClockifyDefaultProjectId;
        ClockifyBillable.IsChecked = _s.ClockifyBillableDefault;
        ClockifyDebug.IsChecked = _s.ClockifyDebug;

        this.PrimaryButtonClick += (sender, e) => Persist();
    }

    private void Persist()
    {
        _s.ViewMode = ViewModeChooser.SelectedIndex == 1 ? "24h" : "9h";
        _s.Source = SourceChooser.SelectedIndex switch
        {
            2 => "clockify",
            1 => "jira-clockify",
            _ => "jira"
        };
        _s.FirstDayOfWeek = FirstDayChooser.SelectedIndex == 1 ? 1 : 0;
        _s.DailyTargetHours = DailyTarget.Value;
        _s.WindowWidth = (int)WinWidth.Value;
        _s.WindowHeight = (int)WinHeight.Value;
        _s.AlwaysOnTop = AlwaysOnTop.IsChecked == true;
        _s.ModalWidth = (int)ModalW.Value;
        _s.ModalHeight = (int)ModalH.Value;

        _s.ShowSprintGauges = ShowGauges.IsChecked == true;
        _s.ShowRingsView = ShowRingsView.IsChecked == true;
        _s.ShowSubtaskTable = ShowSubtaskTable.IsChecked == true;
        _s.SubtaskShowParent = SubtaskShowParent.IsChecked == true;
        _s.SubtaskJql = SubtaskJql.Text ?? "";
        _s.SprintStrategy = SprintStrategyChooser.SelectedIndex switch
        {
            1 => "agile-board",
            2 => "assignee-jql",
            _ => "subtask-customfield"
        };
        _s.SprintField = (SprintField.Text ?? "").Trim();
        _s.SprintBoardId = (int)SprintBoardId.Value;
        _s.RemainingMode = RemainingChooser.SelectedIndex == 1 ? "calculated" : "api";

        _s.JiraSite = (JiraSite.Text ?? "").Trim();
        _s.JiraEmail = (JiraEmail.Text ?? "").Trim();
        _s.JiraToken = JiraToken.Password ?? "";
        _s.JiraIssueJql = JiraJql.Text ?? "";
        _s.JiraIssueMax = (int)JiraIssueMax.Value;
        _s.ShowJiraSummary = JiraShowSummary.IsChecked == true;
        _s.JiraDebug = JiraDebug.IsChecked == true;

        _s.ClockifyApiKey = ClockifyKey.Password ?? "";
        _s.ClockifyWorkspaceId = (ClockifyWorkspace.Text ?? "").Trim();
        _s.ClockifyDefaultProjectId = (ClockifyDefaultProject.Text ?? "").Trim();
        _s.ClockifyBillableDefault = ClockifyBillable.IsChecked == true;
        _s.ClockifyDebug = ClockifyDebug.IsChecked == true;

        SettingsService.Save(_s);
    }
}
