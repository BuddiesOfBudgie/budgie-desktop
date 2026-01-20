# Provides budgie-screenshot component

screenshot_config_data = configuration_data()
screenshot_config_data.set('libexecdir', libexecdir)

screenshot_dialog_desktop = configure_file(
    input: 'budgie-screenshot-dialog.desktop.in.in',
    output: 'budgie-screenshot-dialog.desktop.in',
    configuration: screenshot_config_data,
)

custom_target('desktop-file-screenshot-dialog',
    input : screenshot_dialog_desktop,
    output : 'org.buddiesofbudgie.BudgieScreenshotDialog.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : xdg_appdir)


custom_target('desktop-file-screenshot',
    input : 'budgie-screenshot.desktop.in',
    output : 'org.buddiesofbudgie.BudgieScreenshot.desktop',
    command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir : join_paths(datadir, 'applications'))

# Compile the assets into the binary
screenshot_resources = gnome.compile_resources(
    'budgie-screenshot-resources',
    'budgie-screenshot.gresource.xml',
    source_dir: '.',
    c_name: 'budgie_screenshot',
)

screenshot_sources = [
    'screenshot.vala',
    screenshot_resources
]

screenshot_deps = [
    dep_canberra,
    dep_canberra_gtk3,
    dep_gtk3,
    dep_xfce4windowing,
    dep_gtk_layer_shell,
    dep_gst,
    link_libconfig,
    link_libbudgiewayland,
]

# Need absolute path to gresource
gresource = join_paths(meson.current_source_dir(), 'budgie-screenshot.gresource.xml')

top_vapidir = join_paths(meson.project_source_root(), 'vapi')

screenshot_vala_args = ['-D', 'USE_GSD_DOUBLES']

executable(
    'budgie-screenshot-dialog', screenshot_sources,
    dependencies: screenshot_deps,
    vala_args: [
        '--pkg', 'budgie-config',
        '--vapidir', top_vapidir,
        '--vapidir', dir_libconfig,
        # Make gresource work
        '--target-glib=2.38',
        '--gresources=' + gresource,
        screenshot_vala_args
    ],
    install: true,
    install_dir: libexecdir,
)

main_sources = [
  'screenshot_main.vala',
]

ScreenshotMainDependencies = [
    dep_gtk3,
]

executable(
    'org.buddiesofbudgie.BudgieScreenshot', main_sources,
    dependencies: ScreenshotMainDependencies,
    install: true
)

install_data('org.buddiesofbudgie.budgie-desktop.screenshot.gschema.xml',
    install_dir: join_paths(datadir, 'glib-2.0', 'schemas')
)

install_data('icons/org.buddiesofbudgie.BudgieScreenshot.svg',
    install_dir: join_paths(datadir, 'icons', 'hicolor', 'scalable', 'apps')
)
