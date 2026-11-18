# Security

Report a suspected vulnerability privately through [GitHub Security Advisories](https://github.com/Guydada/OpenDisplay-Lenovo/security/advisories/new). Include the fork version, macOS version, and a minimal description. Remove display serials, device addresses, account names and identifying paths from logs before sharing them.

## What the fork accesses

- Strip control opens a nonexclusive handle to the Lenovo USB controller. It checks the display model, USB vendor and product, feature descriptor, and that a single matching controller and monitor are present. Picture settings use the model-specific DDC binding.
- Choosing **Audio meter** opens a private Core Audio tap for system playback. The callback computes a level in memory. It does not write or transmit audio. Stopping the effect, switching users, sleeping or quitting releases the tap. Playback capture requires macOS permission.
- The Lenovo features add no network listener, remote keyboard pairing, telemetry or update feed. Homebrew fetches and verifies the source before building. The resulting macOS application is locally signed and runs with the current user’s privileges outside the App Sandbox, as required by the inherited display controls. The build enables Hardened Runtime with a library-validation exception for its bundled ad hoc frameworks, which have no Apple signing team. It does not change Gatekeeper or any system security setting.
- Optional upstream features such as global media keys have their own permissions. The current source and its tests are available for review. This is a personal project without an independent security audit or a guaranteed response time.
