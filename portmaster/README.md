# Skyval: first R36H / PortMaster smoke test

This is a **developer test**, not a public release. It checks whether the current
Godot-4 prototype can boot on a real RK3326/ArkOS handheld.

## Platform caveats

PortMaster's current Godot 4.7.1 runtime is **aarch64 only** and requires
`weston_pkg_0.2` to display a Godot 4 window.
Skyval is currently edited with Godot 4.7.2: the 4.7.1 runtime/PCK combination
is **not yet proven on the R36H**. Godot 4 can also be heavy on a 1GB handheld.
The builder uses the already-tested Compatibility renderer and does not bring
900 MB of art to the console.

## Build on the Linux laptop

In the cloned skyval-godot repository, after `git pull`:

```bash
bash tools/build_portmaster.sh
```

The script searches for the editor at:
`$HOME/Godot/res/Godot_v4.7.2-stable_linux.x86_64`

Override any locations explicitly if necessary:

```bash
GODOT_BIN="/path/to/Godot" \
LPC_SPRITES_ROOT="/home/serhii/Godot/res/assets/lpc_sprites" \
bash tools/build_portmaster.sh
```

The script copies project code into a **temporary folder** and copies **only 14**
selected LPC sheets (one body/head/outfit for each gender, shared eyes/hair).
It performs a Godot import and exports `skyval.pck`; your main Godot project's
resources and the huge source art library stay untouched.

For the **absolute smallest engine-only test**:

```bash
bash tools/build_portmaster.sh --no-assets
```

That deliberately shows the old procedural avatar, but tests Godot/Weston boot.

Godot may require its export templates to be installed first via the Godot
editor's `Editor > Manage Export Templates` menu. The generated files are:

```text
dist/portmaster/Skyval_PortMaster_Test.zip
dist/portmaster/roms/ports/
  Skyval.sh
  skyval/
    skyval.pck
    skyval.gptk
    README.txt
```

## Run on the device

1. Ensure PortMaster is installed in ArkOS. In PortMaster's Runtime Manager,
   install **Godot 4.7.1** and **Westonpack 0.2**.
2. Open the generated ZIP and copy **Skyval.sh** plus the **skyval** folder
   into your SD card's `roms/ports/` directory, or `roms2/ports/` if your
   ArkOS configuration uses the second SD card for ROMs.
3. Open **Ports > Skyval** in EmulationStation.

The port uses GPtoKEYB to map:
- **D-pad / left stick**: walk; **right stick**: move the camera's look.
- **Start or X**: open/close the character editor (C key).
- **A**: select/confirm (Enter); **B**: back/close (Esc).
- **L1**: test character mode (4); **R1**: skin tone (5).
- **L2 / R2**: clothing-style debug hotkeys.

If the port closes immediately, the first file to inspect is
`roms/ports/skyval/log.txt`. It shows the native runtime name, failure to
mount Weston or Godot, Godot script errors, and renderer problems. The launcher
will report if it sees a non-aarch64 device.

The runtime's exact executable filename is assumed to follow the documented
Godot naming convention: `godot471.aarch64`. If PortMaster installed a
different executable name, check the listing in `log.txt` and update
`portmaster/Skyval.sh`.

## What counts as a successful first test?

- Skyval starts instead of returning to EmulationStation.
- The 320x240 world is shown at 640x480 without blurring.
- The character moves with the D-pad and the camera follows.
- Start/X opens the creator; D-pad and A can operate its buttons.
- If packed art was found, the actual LPC character (including clothing)
  is visible. If not, the procedural fallback is intentional.

**Not proven by this script:** stable FPS, 1GB memory budget, suspend/resume,
gamepad double input, complete art catalog, performance in populated scenes.

## Sources

- [PortMaster Godot porting notes](https://portmaster.games/contribute/porting/engines/godot/)
- [PortMaster runtime manager](https://portmaster.games/installation/runtimes/)
- [PortMaster gptokeyb controls](https://portmaster.games/gptokeyb-documentation.html)
- [Godot PCK exporting](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

Before distributing a public version, audit the original Universal LPC artwork
licenses and provide the required credits for every asset.
