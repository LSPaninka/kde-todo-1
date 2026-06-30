project('worklog-calendar-py',
  version: '1.0.0',
  meson_version: '>= 0.59.0',
  license: 'MIT',
)

app_id = 'io.github.peperina.WorklogCalendarPy'

gnome = import('gnome')
# PyGObject ('gi') is a runtime dependency installed via apt (python3-gi); it is
# not required at build time, so we don't gate configuration on it here.
python = import('python').find_installation('python3')

prefix = get_option('prefix')
pkgdatadir = prefix / get_option('datadir') / app_id

# Install the Python package next to the app's data.
install_subdir('worklogcalendar',
  install_dir: pkgdatadir,
  exclude_directories: ['__pycache__'],
)

# Generate the launcher (bin/io.github.peperina.WorklogCalendarPy). The shebang
# is `/usr/bin/env python3` so it uses the system Python that carries python3-gi
# (3.12 on Ubuntu 24.04).
conf = configuration_data()
conf.set('pkgdatadir', pkgdatadir)
configure_file(
  input: 'app.in',
  output: app_id,
  configuration: conf,
  install: true,
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

subdir('data')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
)
