gnome = import('gnome')
pkgconfig = import('pkgconfig')

# Compile to CSS dynamically.
sass = find_program('sass', required: false)
sass_args = ['--no-source-map', '--style', 'compressed', '@INPUT@', '@OUTPUT@']
if not sass.found()
    sass = find_program('sassc')
    sass_args = ['--omit-map-comment', '--style', 'compressed', '@INPUT@', '@OUTPUT@']
endif

# Normal and high contrast
theme_variants = [
    '',
    '_hc',
]

theme_deps = []
theme_versions = [
    '3.20',
]

sass_depend_files = files([
    'common/_bluetooth.scss',
    'common/_borders.scss',
    'common/_colors.scss',
    'common/_dialogs.scss',
    'common/_drawing.scss',
    'common/_functions.scss',
    'common/_icon_tasklist.scss',
    'common/_imports.scss',
    'common/_menubar.scss',
    'common/_menu.scss',
    'common/_nightlight.scss',
    'common/_notifications.scss',
    'common/_panel.scss',
    'common/_places.scss',
    'common/_popover.scss',
    'common/_raven.scss',
    'common/_resets.scss',
    'common/_switcher.scss',
    'common/_underscores.scss',
    'common/_workspaces.scss',
    'common/widgets/_base.scss',
    'common/widgets/_button.scss',
    'common/widgets/_calendar.scss',
    'common/widgets/_check_radio.scss',
    'common/widgets/_imports.scss',
    'common/widgets/_linked.scss',
    'common/widgets/_lists.scss',
    'common/widgets/_menu.scss',
    'common/widgets/_progressbar.scss',
    'common/widgets/_scrollbar.scss',
    '3.20/_main.scss',
    '3.20/_resets.scss',
    '3.20/_settings.scss',
    '3.20/_widgets.scss',
])

foreach version : theme_versions
    foreach variant : theme_variants
        # Build the main CSS stylesheet
        theme_deps += custom_target('theme' + variant + '_' + version + '.css',
            input: version + '/theme' + variant + '.scss',
            output: 'theme' + variant + '_' + version + '.css',
            command: [sass] + sass_args,
            depend_files: sass_depend_files,
            build_by_default: true,
        )
    endforeach
endforeach

# Compile the assets into the .so
theme_resources = gnome.compile_resources(
    'budgie-theme-resources',
    'budgie-theme.gresource.xml',
    source_dir: meson.current_build_dir(),
    dependencies: theme_deps,
    c_name: 'budgie_desktop_theme',
)

lib_theme_resources = static_library(
    'budgietheme-resources',
    theme_resources,
    dependencies: [ dep_glib ],
    install: false,
    c_args: ['-Wno-overlength-strings'], # gresource generates overlength strings...
)

theme_sources = [
    'theme.c',
    'theme-manager.c',
]

lib_theme = shared_library(
    'budgietheme',
    theme_sources,
    dependencies: [
        dep_gtk3,
        dep_glib,
    ],
    link_whole: [
        lib_theme_resources,
    ],
    version: '0.0.0',
    install: true,
)

theme_headers = [
    'theme.h',
]

install_headers(theme_headers, subdir: 'budgie-desktop')

# Allow building against libbudgietheme
pkgconfig.generate(
    name: 'Budgie Theme',
    description: 'Budgie Theme Library',
    version: '2',
    filebase: 'budgie-theme-1.0',
    libraries: ['-L${libdir}', '-lbudgietheme'],
    requires: ['gtk+-3.0 >= 3.22.0'],
)

link_libtheme = declare_dependency(
    link_with: lib_theme,
    include_directories: include_directories('.'),
)

# Expose the current directory so that we can use vapidir
dir_libtheme = meson.current_source_dir()
