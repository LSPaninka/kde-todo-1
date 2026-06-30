install_data(
  '@0@.gschema.xml'.format(app_id),
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

configure_file(
  input: 'app.desktop.in',
  output: '@0@.desktop'.format(app_id),
  configuration: { 'APP_ID': app_id },
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

install_data(
  '@0@.svg'.format(app_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

install_data(
  '@0@-symbolic.svg'.format(app_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps',
)
