project(
  'categorized-todo',
  ['vala', 'c'],
  version: '1.0.0',
  license: 'GPL-3.0-or-later',
  meson_version: '>= 0.59.0',
  default_options: ['warning_level=1'],
)

app_id = 'io.github.categorizedtodo'

gnome = import('gnome')

# --- Dependencies -----------------------------------------------------------
glib_dep    = dependency('glib-2.0', version: '>= 2.66')
gobject_dep = dependency('gobject-2.0')
gio_dep     = dependency('gio-2.0')
gtk_dep     = dependency('gtk4', version: '>= 4.10')
adw_dep     = dependency('libadwaita-1', version: '>= 1.2')
soup_dep    = dependency('libsoup-3.0')
json_dep    = dependency('json-glib-1.0')
sqlite_dep  = dependency('sqlite3')
gee_dep     = dependency('gee-0.8')

deps = [
  glib_dep, gobject_dep, gio_dep, gtk_dep, adw_dep,
  soup_dep, json_dep, sqlite_dep, gee_dep,
]

conf_data = configuration_data()
conf_data.set_quoted('APP_ID', app_id)
conf_data.set_quoted('VERSION', meson.project_version())
conf_data.set_quoted('GETTEXT_PACKAGE', 'categorized-todo')
config_h = configure_file(
  output: 'config.h',
  configuration: conf_data,
)
config_dep = declare_dependency(
  sources: config_h,
  include_directories: include_directories('.'),
)
deps += config_dep

subdir('data')
subdir('src')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
)
