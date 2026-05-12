# Contributing to Budgie Desktop

<!-- This document is written for both human contributors and AI coding assistants. -->

All contributors are expected to follow the practices outlined in our [Contributing](https://docs.buddiesofbudgie.org/developer/contributing) documentation. If AI tools or LLMs were used, review our [AI Policy](https://docs.buddiesofbudgie.org/organization/ai-policy) before submitting.

## Getting Started

### Build Quick Reference

```bash
# Clone
git clone https://github.com/BuddiesOfBudgie/budgie-desktop.git && cd budgie-desktop && git submodule update --init

# Configure (generic)
meson build --prefix=/usr --sysconfdir=/etc
# Configure (Arch)
meson setup build --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/lib
# Configure (Debian / Ubuntu)
meson build --prefix=/usr --libdir=/usr/lib
# Configure (Fedora)
meson build --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec
# Configure (Solus)
meson build --prefix=/usr --libdir=/usr/lib64 --sysconfdir=/etc -Dwith-stateless=true --buildtype plain

# Build
ninja -j$(nproc) -C build

# Install
sudo ninja install -C build
```

For full dependency lists and distro-specific packages, see the [build documentation](https://docs.buddiesofbudgie.org/10.10/developer/workflow/building-budgie-desktop/).

## Developer Certificate of Origin (DCO)

All commits must be signed off under the [Developer Certificate of Origin](https://developercertificate.org/) using `git commit -s`. See [DCO.txt](DCO.txt) for the full text and the [Contributing](https://docs.buddiesofbudgie.org/developer/contributing) documentation for details.

## Conventional Commits

All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.

### Format

```
<type>(<scope>): <description>

[optional body]

[optional trailers]
```

### Types

| Type    | Purpose                                        |
| ------- | ---------------------------------------------- |
| `feat`  | A new feature or capability                    |
| `fix`   | A bug fix                                      |
| `docs`  | Documentation only changes                     |
| `chore` | Maintenance tasks, dependency updates, tooling |
| `ci`    | CI/CD configuration changes                    |
| `build` | Build system or external dependency changes    |

### Scopes

Use the most specific scope that fits. For example, use `panel` for panel core changes, `panel/applets` for general applet work, and `icon-tasklist` for a specific applet.

| Scope           | Directory / Area                                                                     |
| --------------- | ------------------------------------------------------------------------------------ |
| `panel`         | `src/panel/` — Panel framework and core                                              |
| `raven`         | `src/raven/` — Notification/widget sidebar                                           |
| `daemon`        | `src/daemon/` — Background daemon                                                    |
| `session`       | `src/session/`, `src/libsession/` — Session management                               |
| `theme`         | `src/theme/` — Theming engine                                                        |
| `windowing`     | `src/windowing/` — Windowing abstractions                                            |
| `appindexer`    | `src/appindexer/` — Application indexing                                             |
| `lib`           | `src/lib/` — Shared library                                                          |
| `<dialog-name>` | `src/dialog/<dialog-name>` — Changes to specific dialogs                             |
| `panel/applets` | `src/panel/applets/` — General panel applet changes                                  |
| `<applet-name>` | `src/panel/applets/<name>/` — Specific applet (e.g., `icon-tasklist`, `budgie-menu`) |
| `raven/widgets` | `src/raven/widgets/` — General Raven widget changes                                  |
| `<widget-name>` | `src/raven/widgets/<name>/` — Specific widget (e.g., `calendar`, `media-controls`)   |
| `config`        | `src/config/` — Configuration                                                        |
| `bridges`       | `src/bridges/` — Bridge interfaces                                                   |
| `data`          | `data/` — Data files, schemas, desktop entries                                       |
| `docs`          | `docs/` — Documentation, man pages                                                   |
| `build`         | `meson.build`, `meson_options.txt` — Build system                                    |
| `ci`            | `.github/` — CI/CD workflows                                                         |

### Rules

- Description: lowercase, imperative mood (write as a command, e.g., "add feature" not "added feature" or "adds feature"), no trailing period
- Keep the first line under 72 characters
- The body should explain **why**, not what — the diff shows what changed

## AI Policy

Contributors may use AI tools (Claude, Gemini, Copilot, ChatGPT, etc.) as part of their workflow. If you have used AI tools or LLMs as part of your contribution, you are expected to have read and understood the full [AI Policy](https://docs.buddiesofbudgie.org/organization/ai-policy) before submitting. The key rules:

- All contributions must be tested before submission
- Non-trivial AI-assisted code must be built, installed, and tested by the contributor
- All commits must be signed off under the [DCO](DCO.txt) using `git commit -s`
- Use `Assisted-by: <Tool>:<model-id>` commit trailers when AI wrote, generated, or substantially modified code
- Using AI for research only (human wrote all code) does not require attribution
- Intentional obfuscation of AI tooling usage is grounds for rejection and may result in being blocked from future contributions

For detailed attribution guidance and examples, see the full [AI Policy](https://docs.buddiesofbudgie.org/organization/ai-policy).

## Pull Requests

- Provide a clear description explaining **what** changed and **why**
- Include a test plan describing how you verified the changes
- See the [pull request template](.github/PULL_REQUEST_TEMPLATE.md) for the expected format
- If AI tools were used for code changes, ensure commits include the appropriate `Assisted-by` trailer
- Supplemental comments on the PR with AI prompt/planning information are welcome and encouraged for research and learnings, but not mandatory. These should be shared as PR comments, not committed to the repository.
