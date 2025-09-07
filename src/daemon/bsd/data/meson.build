schemas = [
#  'org.gnome.settings-daemon.global-shortcuts.gschema.xml',
#  'org.gnome.settings-daemon.peripherals.gschema.xml',
#  'org.gnome.settings-daemon.peripherals.wacom.gschema.xml',
#  'org.gnome.settings-daemon.plugins.gschema.xml',
#  'org.gnome.settings-daemon.plugins.color.gschema.xml',
#  'org.gnome.settings-daemon.plugins.housekeeping.gschema.xml',
  'org.buddiesofbudgie.settings-daemon.plugins.media-keys.gschema.xml',
#  'org.gnome.settings-daemon.plugins.power.gschema.xml',
#  'org.gnome.settings-daemon.plugins.sharing.gschema.xml',
#  'org.gnome.settings-daemon.plugins.xsettings.gschema.xml'
]

if enable_wwan
  schemas += 'org.gnome.settings-daemon.plugins.wwan.gschema.xml'
endif

schema_conf = configuration_data()
schema_conf.set('GETTEXT_PACKAGE', gsd_name)

schemas_xml = []
foreach schema: schemas
  schemas_xml += [configure_file(
    input: schema + '.in',
    output: schema,
    configuration: schema_conf,
    install_dir: gsd_schemadir
  )]
endforeach

enums_header = files('gnome-settings-daemon' / 'gsd-enums.h')

#mkenums = gnome.mkenums(
#  'org.gnome.settings-daemon.enums.xml',
#  sources: enums_header,
#  comments: '<!-- @comment@ -->',
#  fhead: '<schemalist>',
#  vhead: '  <@type@ id="org.gnome.settings-daemon.@EnumName@">',
#  vprod: '    <value nick="@valuenick@" value="@valuenum@"/>',
#  vtail: '  </@type@>',
#  ftail: '</schemalist>',
#  install_header: true,
#  install_dir: gsd_schemadir
#)

install_data(
  enums_header,
  install_dir: join_paths(gsd_pkgincludedir, gsd_name)
)

#install_data(
#  'gnome-settings-daemon.convert',
#  install_dir: join_paths(gsd_datadir, 'GConf', 'gsettings')
#)

pkg.generate(
  version: gsd_version,
  name: gsd_name,
  description: gsd_name + ' specific enumerations',
  filebase: gsd_name,
  subdirs: gsd_api_name
)

gsd_enums_dep = declare_dependency(
  include_directories: include_directories('.')
)

#meson.override_dependency(meson.project_name(), gsd_enums_dep)

# for unit tests - gnome.compile_schemas() only looks in srcdir
#custom_target('compile-schemas',
#  input: schemas_xml,
#  depends: mkenums,
#  output: 'gschemas.compiled',
#  command: [find_program('glib-compile-schemas'), meson.current_build_dir()],
#  build_by_default: true)
