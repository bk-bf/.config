# GRUB — Auto-select Highest galaxybook Kernel

## Problem

Two separate issues had to be solved:

1. `GRUB_TOP_LEVEL` in `/etc/default/grub` is a static path. After installing a new
   `cachyos-galaxybook-kernel` version the path is stale — the old kernel stays first
   in the boot menu until manually updated.

2. `GRUB_DEFAULT=saved` causes GRUB to restore `grubenv`'s `saved_entry` on every
   boot. That variable was set to the advanced submenu path
   (`gnulinux-advanced-...>gnulinux-cachyos-galaxybook-kernel-advanced-...`), which
   locked the cursor on the "Advanced options" submenu entry regardless of menu order
   or `GRUB_TOP_LEVEL`. It survives `grub-mkconfig` — `grubenv` is a separate file.

---

## Solution

**`grub/galaxybook-top-level.cfg`** — a shell snippet dropped into
`/etc/default/grub.d/`. `grub-mkconfig` **sources** all `*.cfg` files from that
directory into its own shell before executing any `grub.d/` scripts. This means
`GRUB_TOP_LEVEL` is set in the correct process when `10_linux` runs and calls
`grub_move_to_front`, placing the galaxybook kernel at position 0.

> **Why not `/etc/grub.d/`?** Scripts there are executed as subprocesses (`"$i"`).
> An `export` in a child process cannot affect the parent shell's environment, so
> `GRUB_TOP_LEVEL` would never reach `10_linux`. `/etc/default/grub.d/` is the
> correct hook — it is sourced, not executed.

**`GRUB_DEFAULT=0`** — always boots position 0 unconditionally. Eliminates the
`saved_entry` problem entirely; `grubenv` is ignored for default selection.

Together: `grub-mkconfig` always puts the highest galaxybook kernel at position 0,
and GRUB always boots position 0. No manual intervention after a kernel upgrade.

---

## Files

| Dotfile source                     | System path                                           |
| ---------------------------------- | ----------------------------------------------------- |
| `grub/grub`                        | `/etc/default/grub` (symlinked by install.sh)         |
| `grub/galaxybook-top-level.cfg`    | `/etc/default/grub.d/galaxybook-top-level.cfg` (installed by install.sh) |

`GRUB_TOP_LEVEL` is **not** set in `grub/grub` — `galaxybook-top-level.cfg` sets it
at runtime. `GRUB_SAVEDEFAULT` is intentionally not set.

---

## Restore

```bash
sudo ln -sf ~/.config/grub/grub /etc/default/grub
sudo mkdir -p /etc/default/grub.d
sudo install -m 0644 ~/.config/grub/galaxybook-top-level.cfg /etc/default/grub.d/galaxybook-top-level.cfg
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo grub-editenv /boot/grub/grubenv unset saved_entry
```

The last line clears any stale `saved_entry` left by a previous `GRUB_DEFAULT=saved`
setup or a manual `grub-set-default` call.

---

## Related

- [SYSTEM_SYMLINKS.md](../SYSTEM_SYMLINKS.md) — general pattern for tracked system files
- [../custom-kernel/CUSTOM_KERNEL.md](../../.custom-kernel/CUSTOM_KERNEL.md) — install-kernel.sh calls grub-mkconfig automatically
