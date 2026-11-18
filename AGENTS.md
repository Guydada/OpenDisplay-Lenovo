# OpenDisplay Lenovo

Read the [project README](README.md) and [hardware notes](Docs/Compatibility/Lenovo-Y34wz-30.md). Keep the menu-bar display card, settings, CLI and shared providers as the integration points. Match OpenDisplay’s existing controls.

- Identify the Lenovo model on both the display and DDC binding before sending model-specific settings. Keep indexed DDC writes together under the bus lock.
- Use the dedicated USB feature transport for strip colors. Require one matching monitor and controller. Report successful writes and physical observations separately.
- Start hardware checks with `lenovo <selector> lighting-status` and `color … --dry-run`. Live changes require a deliberate operator action.
- Run `make test`, `scripts/build-lenovo-local.sh`, `scripts/test-lenovo-lighting.sh` and the OpenDisplay-PublicAPIOnly scheme locally. Use one running app copy at a time because upstream and the fork share an app identity.
- Keep distribution source-based. Version the app in `project.yml` and pin the matching source archive and SHA-256 in the Homebrew formula.
