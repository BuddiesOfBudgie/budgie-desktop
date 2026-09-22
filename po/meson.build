# Read the languages from the LINGUAS file
langs = fs.read('LINGUAS').strip().split('\n')

# Stole this from gnome-twitch, ty TingPing
# https://github.com/vinszent/gnome-twitch/tree/master/po
xgettext_args = [
    '--from-code=UTF-8',
    '--add-comments',
    # i18n.xgettext hands the files over in an unordered set
    '--sort-by-file',
    '--no-wrap',
    '--package-name=' + meson.project_name(),
    '--package-version=' + meson.project_version(),
    '--keyword=_',
    '--keyword=N_',
    '--keyword=C_:1c,2',
    '--keyword=NC_:1c,2',
    '--keyword=g_dcgettext:2',
    '--keyword=g_dngettext:2,3',
    '--keyword=g_dpgettext2:2c,3',
    '--keyword=Description',

    '--flag=N_:1:pass-c-format',
    '--flag=C_:2:pass-c-format',
    '--flag=NC_:2:pass-c-format',
    '--flag=g_dngettext:2:pass-c-format',
    '--flag=g_strdup_printf:1:c-format',
    '--flag=g_string_printf:2:c-format',
    '--flag=g_string_append_printf:2:c-format',
    '--flag=g_error_new:3:c-format',
    '--flag=g_set_error:4:c-format',
]

# its budgie-desktop-pot target wants a POTFILES and fails; use budgie-desktop.pot
i18n.gettext(meson.project_name(), languages: langs, args: xgettext_args)

# meson rejects an unknown method at configure time, whether or not it is built
if meson.version().version_compare('>= 1.8.0')
    i18n.xgettext(
        meson.project_name(),
        budgie_pot_targets,
        budgie_pot_ui,
        budgie_pot_templates,
        args: xgettext_args,
    )
else
    message('meson >= 1.8.0 is needed to regenerate budgie-desktop.pot')
endif
