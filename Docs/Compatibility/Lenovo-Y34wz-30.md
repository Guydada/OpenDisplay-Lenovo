# Lenovo Legion Y34wz-30

## Observed behavior

| Test | Result |
| --- | --- |
| Detection | The display advertises EDID vendor LEN and product 67B0. USB lighting and the DDC picture controls use separate connections. |
| Picture controls | Game mode, HDR and dynamic contrast could be read. Turning dynamic contrast off was confirmed by readback. Other mode values have not been individually verified. |
| USB color | A solid red frame lit the strip red. Spectrum showed multiple colors at once. The panel has no verified palette readback. |
| Motion and audio | A 15-second Marquee test showed a bright band moving across the Ocean palette. Audio meter followed system playback. |
| Firmware effects | Rainbow was observed over DDC. Some other firmware effects appeared dark or static. Menu-bar effects use USB animation. |
| Open questions | Physical zone orientation and behavior across sleep or monitor power cycles. |

## Lighting protocol

The CLI command `lenovo <selector> effect <name>` selects VCP `0xF8 = 0x001D` and sends the effect number to `0xF7` under the DDC bus lock. Rainbow was observed on this unit. The earlier DDC color hypothesis failed both visual checks. The strip brightness slider uses USB. The register reference reports that out-of-range DDC writes to `0x051D` can leave the strip persistently dim. [Y34wz-30 register reference](https://github.com/Ferroman/lenovo-y34wz-cli/blob/28705fe98007a24f11d0eea9462b1c1228d02806/docs/reference.md)

Lenovo Accessories and Display Manager 1.0.13.05 lists model `67B0` and selects `USBLedLightCtrl1` for the Y34wz-30. For “No Animation”, its service constructs a frame with mode 1, speed 0, brightness 0–100 and six RGB colors. The model-specific DLL passes the 168 bytes to Windows `HidD_SetFeature`. The installed macOS SDK specifies that the report ID belongs in both the ID argument and the first byte of a numbered report. [Lenovo Windows installer](https://download.lenovo.com/consumer/monitor/lenovo_accessories_and_display_manager_v1_0_13_05_setup.exe) · [Apple IOHIDDeviceSetReport](https://developer.apple.com/documentation/iokit/1588517-iohiddevicesetreport)

| Feature report bytes (zero-based) | Value |
| --- | --- |
| 0 | Report ID `0x72` |
| 12, 16, 17 | Static mode `1`, speed `0`, strip brightness |
| 95–139 | Fifteen RGB triplets. The six zone colors occupy 3, 2, 3, 2, 3 and 2 triplets respectively. |
| Other bytes | Fixed vendor frame values covered by byte-for-byte tests. |

**Verification.** The installer SHA-256 was `c0000e4e479d66bca869106ae0642f057c8f44cb4c0c4048213e60f7e1d6ed84`. In its control service, model selection is at VA `0x1401D5640`, static frame mode and speed at `0x1401D5076`, and the USB encoder at `0x140329960`. The DLL export `_SetLEDSetting` calls `HidD_SetFeature`. Running only the encoder in an isolated CPU emulator, stopping before the HID call, produced independent fixtures. The 168-byte report for `#123456` at 42% has SHA-256 `c533a1ae8d1b45eb1de2d9d90a5d86958e4e610493b50730caa5c1145c067c5b`. The unit tests include that complete frame and a six-color palette.

**Device selection.** The monitor exposes USB `17ef:10ac` with a vendor feature on usage page `0xFF00`, usage 1, ID `0x72` and 167 payload bytes. Discovery checks this descriptor without opening the controller for writes. The USB controller and the video EDID have separate identities, so the supported setup has one online Y34wz-30 and one matching USB controller. The app checks both identities when it opens an animation writer, holds a non-exclusive handle to that USB controller, and periodically rechecks the connection. The editor coalesces drag events, sends only changed animation frames at up to ten per second, and remembers accepted color and motion settings. Opening either surface only restores the controls. An animation or system audio tap starts when the user selects it. Relaunch and system sleep stop playback. The strip has no verified palette readback.

## Color, motion and audio

The color swatch directly selects any solid RGB color. The palette button recalls built-in and saved six-zone palettes. **Effect** controls motion independently. **Steady** shows the selected colors directly. **Marquee** moves a bright band across the zones and also works with a single color. In Settings, **Custom wave** blends the selected colors around the strip with adjustable cycle length and direction. In **Settings → Displays → Lenovo Legion → Saved palettes**, **Add palette…** opens a name and six color wells. Edit or delete saved palettes there. The previous **My palette** entry migrates into the named library.

**Audio meter** lights successive zones with the volume of audio playing on this Mac. On macOS 14.2 and later, selecting it opens a private Core Audio process tap using System Audio Recording permission. Playback continues on the current output. The app measures Float32 samples in memory, keeps only the latest level and releases capture when the effect stops. In silence the meter fades to dark. If sound is playing but the meter stays quiet, check OpenDisplay in **System Settings → Privacy & Security → Screen & System Audio Recording**. [Apple audio tap documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
