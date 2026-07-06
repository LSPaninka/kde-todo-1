sources = files(
  'config.vapi',
  'main.vala',
  'Application.vala',
  'Config.vala',
  'Models.vala',
  'Database.vala',
  'TaskStore.vala',
  'JiraStore.vala',
  'GhStore.vala',
  'NotionSyncStore.vala',
  'tray/Tray.vala',
  'ui/Widgets.vala',
  'ui/TodoView.vala',
  'ui/JiraView.vala',
  'ui/GhView.vala',
  'ui/TaskEditDialog.vala',
  'ui/Preferences.vala',
  'ui/PopupWindow.vala',
  'ui/MainWindow.vala',
)

executable(
  'categorized-todo',
  sources,
  dependencies: deps,
  vala_args: [
    '--target-glib=2.66',
    '--pkg', 'posix',
  ],
  install: true,
)
