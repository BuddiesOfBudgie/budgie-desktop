# Budgie Desktop — AI Agent Documentation

This document provides technical context for AI coding assistants working on Budgie Desktop. For contribution practices, see the [Contributing](https://docs.buddiesofbudgie.org/developer/contributing) documentation. For AI usage guidelines, see the [AI Policy](https://docs.buddiesofbudgie.org/organization/ai-policy).

## Project Identity

- **Project**: Budgie Desktop 10.10
- **Type**: Wayland-only desktop environment
- **Languages**: C and Vala
- **Build system**: Meson + Ninja
- **UI toolkit**: GTK 3.24+

## Build Quick Reference

```bash
# Configure
meson build --prefix=/usr --sysconfdir=/etc

# Build
ninja -j$(nproc) -C build

# Install
sudo ninja install -C build
```

### Meson Options

See [`meson_options.txt`](meson_options.txt) for available build options.

For full dependency lists and distro-specific packages, see the [build documentation](https://docs.buddiesofbudgie.org/10.10/developer/workflow/building-budgie-desktop/).

## Repository Structure

### Source Directories (`src/`)

| Directory | Purpose | Commit Scope |
|-----------|---------|--------------|
| `src/panel/` | Panel framework and core | `panel` |
| `src/panel/applets/` | Panel applets (see below) | `panel/applets` or `<applet-name>` |
| `src/raven/` | Notification/widget sidebar | `raven` |
| `src/raven/widgets/` | Raven widgets (see below) | `raven/widgets` or `<widget-name>` |
| `src/daemon/` | Background daemon | `daemon` |
| `src/wm/` | Window management | `wm` |
| `src/session/` | Session management | `session` |
| `src/libsession/` | Session library | `session` |
| `src/theme/` | Theming engine | `theme` |
| `src/windowing/` | Windowing abstractions | `windowing` |
| `src/appindexer/` | Application indexing | `appindexer` |
| `src/dialogs/` | Dialogs (polkit, power, run, screenshot, sendto) | `dialogs` |
| `src/lib/` | Shared library | `lib` |
| `src/config/` | Configuration | `config` |
| `src/bridges/` | Bridge interfaces | `bridges` |
| `src/appsys/` | Application system | `appsys` |
| `src/plugin/` | Plugin system | `plugin` |

### Panel Applets (`src/panel/applets/`)

budgie-menu, caffeine, clock, icon-tasklist, keyboard-layout, lock-keys, night-light, notifications, places-indicator, raven-trigger, separator, show-desktop, spacer, status, tasklist, trash, tray, user-indicator, workspaces

### Raven Widgets (`src/raven/widgets/`)

calendar, media-controls, sound-input, sound-output, usage-monitor

### Other Key Directories

| Directory | Purpose | Commit Scope |
|-----------|---------|--------------|
| `data/` | Data files, schemas, desktop entries | `data` |
| `docs/` | Documentation, man pages | `docs` |
| `po/` | Translations | `i18n` |
| `vapi/` | Vala API bindings | `vapi` |
| `subprojects/` | Git submodules | varies |

## Wayland Context

Budgie 10.10 is **Wayland-only** and uses [labwc](https://labwc.github.io/) as its compositor.

### Required Protocols

- `ext-workspace-v1` — Workspace management
- `wlr-foreign-toplevel-management` — Toplevel window tracking
- `wlr-layer-shell` — Layer surfaces (panels, overlays)
- `wlr-output-management` — Output/display configuration
- `xdg-output` — Logical output information

### Positioning

Uses [gtk-layer-shell](https://github.com/wmww/gtk-layer-shell) for panel and overlay positioning on Wayland.

## Fetching External Resources

Agents should web fetch these resources when relevant to the task:

- **Build docs**: https://docs.buddiesofbudgie.org/10.10/developer/workflow/building-budgie-desktop/ — for dependency lists and distro-specific setup
- **Contributing**: https://docs.buddiesofbudgie.org/developer/contributing — for DCO, sign-off, and contribution requirements
- **AI Policy**: https://docs.buddiesofbudgie.org/organization/ai-policy — for attribution requirements and AI usage guidelines
- **GTK 3 API reference**: https://docs.gtk.org/gtk3/ — for UI widget and API questions
- **Vala language reference**: https://vala.dev/tutorials/programming-language/main/ — for language-specific syntax and patterns

## Attribution and Sign-off

All commits must include a `Signed-off-by` trailer. Use `git commit -s` to add it automatically.

When committing, the agent must analyze the conversation context to determine whether it actually assisted with code changes (writing, modifying, or generating code). If so, add an `Assisted-by` trailer. Mechanical tasks (committing, formatting, running commands) do not constitute code assistance and do not require the trailer. Fetch the [AI Policy](https://docs.buddiesofbudgie.org/organization/ai-policy) for full attribution guidance.

## Code Conventions

- Follow existing patterns in the codebase
- **Vala naming**: PascalCase for classes and interfaces, snake_case for methods and variables
- **C naming**: `budgie_` prefix for public API functions
- Refer to surrounding code in the same file/module for style guidance
