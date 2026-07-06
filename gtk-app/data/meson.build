# GSettings schema
install_data(
  '@0@.gschema.xml'.format(app_id),
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# Desktop launcher
install_data(
  '@0@.desktop'.format(app_id),
  install_dir: get_option('datadir') / 'applications',
)

# AppStream metainfo
install_data(
  '@0@.metainfo.xml'.format(app_id),
  install_dir: get_option('datadir') / 'metainfo',
)

# Icons
install_data(
  'icons/hicolor/scalable/apps/@0@.svg'.format(app_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)
install_data(
  'icons/hicolor/symbolic/apps/@0@-symbolic.svg'.format(app_id),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps',
)
