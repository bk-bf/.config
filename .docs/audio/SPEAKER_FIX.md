# Galaxy Book 4 Ultra — MAX98390 Speaker Fix

## Hardware

The Galaxy Book 4 Ultra has four MAX98390 amplifier chips on I2C bus 2:

| Address | Created by |
|---------|------------|
| `0x38`  | ACPI/BIOS firmware unconditionally at boot (`i2c-MAX98390:00`) |
| `0x39`  | `max98390-hda-i2c-setup.service` (runtime, on start) |
| `0x3c`  | `max98390-hda-i2c-setup.service` (runtime, on start) |
| `0x3d`  | `max98390-hda-i2c-setup.service` (runtime, on start) |

The codec is a Realtek ALC298. Pin `0x17` routes to the speakers; pin `0x21` is headphone.

The Intel audio DSP requires SOF firmware (`sof-firmware` package) to function at all.

---

## The Fix

Out-of-tree DKMS module from
[samsung-galaxy-book-linux-fixes](https://github.com/Dreaming-Codes/samsung-galaxy-book-linux-fixes):

- **Source:** `samsung-galaxy-book-linux-fixes-main/speaker-fix/`
- **DKMS module:** `max98390-hda / 1.0`
- **Kernel module loaded:** `snd-hda-scodec-max98390`

The installer does:
1. Copies source to `/usr/src/max98390-hda-1.0/`, registers, builds, and installs via DKMS.
2. Drops `/etc/modules-load.d/max98390-hda.conf` to autoload the module.
3. Installs and enables `max98390-hda-i2c-setup.service` which runs
   `/usr/local/sbin/max98390-hda-i2c-setup.sh` to instantiate the three non-ACPI amps.

The i2c setup script probes addresses `0x39`, `0x3c`, `0x3d` with `i2cget` and writes
`max98390-hda <addr>` to `/sys/bus/i2c/devices/i2c-2/new_device` for each that ACKs.
`0x38` is skipped because ACPI already created it.

---

## Three Observed States

### State 1 — True baseline (no installer)

No DKMS module, no i2c service, no `modules-load.d` entry.

- ALC298 autoconfig: `line_outs=1 (0x17)`, `speaker_outs=0`
- Only the ACPI-created `0x38` device exists; no driver binds to it.
- Result: **no speakers** (confirmed from original setup experience; direct logs not captured).

### State 2 — Partial (installer artifacts present, DKMS absent for running kernel)

This occurs when the installer was run from a different kernel than the one currently booting.
The installer's `dkms remove --all` wipes all existing builds; it then rebuilds only for the
running kernel. Any other kernel boots without a `.ko`.

Artifacts on disk: `/etc/modules-load.d/max98390-hda.conf` and the i2c service — both
persist across boots regardless of which kernel is running.

Boot sequence:
1. `systemd-modules-load` attempts to load `snd_hda_scodec_max98390` → **fails**
   (`Failed to find module 'snd_hda_scodec_max98390'` in journal).
2. `max98390-hda-i2c-setup.service` **still runs** and instantiates `0x39`, `0x3c`, `0x3d`.
3. No driver binds to any of the four devices.
4. ALC298 autoconfig: `line_outs=1 (0x17)`, `speaker_outs=0`.
5. **Actual audio output in this state was not tested** — speaker behavior is unknown.
   The current broken state (post-LTS-installer-run, booting CachyOS) matches this
   description structurally, but what the user hears has not been confirmed in logs.

### State 3 — Fully working (DKMS built for running kernel)

Verified on `6.19.10-1-cachyos`. Boot sequence with approximate monotonic timestamps:

1. **~4.94 s** — `systemd-modules-load` inserts `i2c_dev`, then `snd_hda_scodec_max98390`
   (out-of-tree, taints kernel — expected), then `snd_hda_scodec_max98390_i2c`.
2. **~4.96 s** — Driver immediately probes the ACPI-created device:
   `MAX98390 HDA I2C probe: addr=0x38 index=0 name=i2c-MAX98390:00`
3. **~6.77 s** — SOF firmware and topology loaded:
   - Firmware: `intel/sof-ipc4/mtl/sof-mtl.ri` (version 2.14.1.1)
   - Topology: `intel/sof-ipc4-tplg/sof-hda-generic-2ch.tplg`
4. **~6.92 s** — ALC298 autoconfig:
   `line_outs=1 (0x17) type:speaker`, `speaker_outs=0`, `hp_outs=1 (0x21)`, `Mic=0x18`
   *(speaker_outs=0 is normal here — the four MAX98390 amps are the actual speaker output
   path via HDA codec widgets, not counted as discrete speaker_outs)*
5. **~7.55 s** — `max98390-hda-i2c-setup.service` starts.
6. **~7.58 s** — Script finds 3 additional amplifiers on bus 2: `0x39 0x3c 0x3d`.
7. **~7.58–8.33 s** — Each amp instantiated and probed in sequence:
   - `2-0039`: `MAX98390 HDA I2C probe: addr=0x39 index=1`
   - `2-003c`: `MAX98390 HDA I2C probe: addr=0x3c index=2`
   - `2-003d`: `MAX98390 HDA I2C probe: addr=0x3d index=3`
8. **~8.33 s** — Service finishes; `Sound Card` target reached.
9. **~12.5 s** — `max98390-hda-check-upstream.service` confirms the DKMS workaround is
   still required for `6.19.10-1-cachyos` — upstream kernel does not yet carry the driver.

Result: **both speakers, full volume**.

---

## How the Partial State Occurs (Root Cause)

The installer (`install.sh` line 122) calls `dkms remove max98390-hda/1.0 --all` before
rebuilding. This wipes DKMS builds for **all kernels**, then rebuilds only for the one
currently running.

What happened in practice:
1. Installer was originally run from the CachyOS kernel → working DKMS build for CachyOS.
2. System accidentally booted into LTS kernel.
3. Installer was re-run from LTS → `dkms remove --all` wiped the CachyOS build → rebuilt
   only for LTS.
4. On next boot back into CachyOS, no `.ko` exists — partial state.

Note: Speaker behavior on LTS was never tested; the LTS boot was accidental and the machine
was rebooted back to CachyOS without verifying audio.

---

## Fix / Recovery

Identify which kernel you boot into normally:

```bash
uname -r          # currently running
```

Build the DKMS module for that kernel:

```bash
sudo dkms build -m max98390-hda/1.0 -k $(uname -r)
sudo dkms install -m max98390-hda/1.0 -k $(uname -r)
```

Then reload without rebooting:

```bash
sudo modprobe snd-hda-scodec-max98390
sudo systemctl restart max98390-hda-i2c-setup.service
```

Or just reboot.

To verify DKMS has builds for all kernels you use:

```bash
dkms status max98390-hda/1.0
```

---

## SOF Topology Note

Two different SOF topology paths have been observed depending on the kernel:

| Kernel | Topology path |
|--------|---------------|
| LTS (`linux-lts`) | `intel/sof-ace-tplg/sof-hda-generic-2ch.tplg` |
| CachyOS (`linux-cachyos`) | `intel/sof-ipc4-tplg/sof-hda-generic-2ch.tplg` |

Both use the same filename (`sof-hda-generic-2ch.tplg`) from different parent directories
(`sof-ace-tplg` vs `sof-ipc4-tplg`). The significance of this difference on speaker
behaviour is unclear and has not been investigated further.

---

## Relevant Paths

| Path | Purpose |
|------|---------|
| `samsung-galaxy-book-linux-fixes-main/speaker-fix/install.sh` | Installer |
| `samsung-galaxy-book-linux-fixes-main/speaker-fix/max98390-hda-i2c-setup.sh` | I2C device creation script |
| `/usr/src/max98390-hda-1.0/` | DKMS source tree |
| `/etc/modules-load.d/max98390-hda.conf` | Module autoload config (dropped by installer) |
| `/etc/systemd/system/max98390-hda-i2c-setup.service` | I2C setup service |
| `/usr/local/sbin/max98390-hda-i2c-setup.sh` | I2C setup script (installed copy) |
