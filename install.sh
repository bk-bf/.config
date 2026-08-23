#!/bin/bash
# Post-clone setup script. Run once on a new machine after cloning the repo.
# Usage: bash ~/.config/install.sh
#
# Full restore from scratch:
#   git clone https://github.com/bk-bf/.config.git ~/.config && bash ~/.config/install.sh

set -e

CONFIG="$HOME/.config"
WARNINGS=()

# ── Hardware detection ────────────────────────────────────────────────────────

IS_LAPTOP=false
IS_GALAXY_BOOK=false
IS_HIDPI_LAPTOP=false  # laptop internal eDP display with height > 1200px
CPU_VENDOR="unknown"   # intel | amd | unknown
GPU_VENDOR="unknown"   # intel | amd | nvidia | unknown

# Laptop: battery present
ls /sys/class/power_supply/BAT* &>/dev/null 2>&1 && IS_LAPTOP=true

# Galaxy Book: DMI product name
[[ "$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)" == *"Galaxy Book"* ]] \
    && IS_GALAXY_BOOK=true

# CPU vendor
case "$(grep -m1 vendor_id /proc/cpuinfo 2>/dev/null)" in
    *GenuineIntel*) CPU_VENDOR="intel" ;;
    *AuthenticAMD*) CPU_VENDOR="amd"   ;;
esac

# GPU vendor: check loaded DRM modules
if lsmod 2>/dev/null | grep -q "^nvidia"; then
    GPU_VENDOR="nvidia"
elif lsmod 2>/dev/null | grep -q "^amdgpu"; then
    GPU_VENDOR="amd"
elif lsmod 2>/dev/null | grep -q "^i915"; then
    GPU_VENDOR="intel"
fi

# HiDPI laptop: eDP connector (always internal laptop display, never desktop) + height > 1200px
# Handles Galaxy Book Gen4 and any future HiDPI laptop without hardcoding model names
if $IS_LAPTOP; then
    for modes in /sys/class/drm/card*-eDP-*/modes; do
        [[ -f "$modes" ]] || continue
        height=$(head -1 "$modes" 2>/dev/null | grep -oP 'x\K[0-9]+' || true)
        [[ -n "$height" && "$height" -gt 1200 ]] && IS_HIDPI_LAPTOP=true && break
    done
fi

echo "==> Hardware detected:"
echo "    laptop       = $IS_LAPTOP"
echo "    galaxy_book  = $IS_GALAXY_BOOK"
echo "    hidpi_laptop = $IS_HIDPI_LAPTOP"
echo "    cpu          = $CPU_VENDOR"
echo "    gpu          = $GPU_VENDOR"

# ── Package installation ──────────────────────────────────────────────────────

echo ""
echo "==> Installing packages from pkglist.txt..."
if command -v yay &>/dev/null; then
    yay -S --needed - < "$CONFIG/pkglist.txt"
elif command -v paru &>/dev/null; then
    echo "    yay not found, falling back to paru..."
    paru -S --needed - < "$CONFIG/pkglist.txt"
else
    echo ""
    echo "    !! No AUR helper found (tried: yay, paru)."
    echo "    !! Bootstrap yay first, then re-run this script:"
    echo ""
    echo "       sudo pacman -S --needed git base-devel"
    echo "       git clone https://aur.archlinux.org/yay.git /tmp/yay"
    echo "       cd /tmp/yay && makepkg -si"
    echo "       cd ~/.config && bash install.sh"
    echo ""
    exit 1
fi

# ── SDDM config ───────────────────────────────────────────────────────────────

echo ""
echo "==> Configuring SDDM..."

# QT_SCALE_FACTOR=2 applies to any HiDPI laptop (eDP display, height > 1200px)
# Galaxy Book Gen4 is the current case; any future HiDPI laptop triggers this too
SCALE_ENV=""
$IS_HIDPI_LAPTOP && SCALE_ENV=",QT_SCALE_FACTOR=2"

sudo tee /etc/sddm.conf > /dev/null <<EOF
[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard${SCALE_ENV}

[Theme]
Current=silent
EOF
echo "    Written /etc/sddm.conf (QT_SCALE_FACTOR=2: $IS_HIDPI_LAPTOP)"
$IS_HIDPI_LAPTOP || WARNINGS+=("sddm: if SDDM greeter appears too small, add QT_SCALE_FACTOR=2 to GreeterEnvironment in /etc/sddm.conf")

# SDDM login wallpaper follows noctalia's current wallpaper. The silent theme's
# default.conf already points background="wallpaper.png"; a root watcher service
# overwrites that file whenever noctalia changes wallpaper (greeter runs as user
# `sddm` and can't read $HOME, hence the copy into the theme dir).
sudo ln -sf "$CONFIG/sddm/wallpaper-sync.sh" /usr/local/bin/sddm-wallpaper-sync.sh
sudo ln -sf "$CONFIG/sddm/wallpaper-sync.service" /etc/systemd/system/sddm-wallpaper-sync.service
sudo systemctl enable --now sddm-wallpaper-sync.service
echo "    sddm wallpaper-sync → enabled (follows noctalia)"

# ── Pacman hook ───────────────────────────────────────────────────────────────

echo ""
echo "==> Creating system symlinks..."
sudo mkdir -p /etc/pacman.d/hooks
sudo ln -sf "$CONFIG/pkg-tracker.hook" /etc/pacman.d/hooks/pkg-tracker.hook

# ── Mirror refresh ────────────────────────────────────────────────────────────
# cachyos-rate-mirrors.timer is Persistent=true, so a due date inside a suspend
# window fires at wake, before NetworkManager reconnects. The drop-in waits for
# connectivity so the script's geoip lookup has a resolver.

sudo mkdir -p /etc/systemd/system/cachyos-rate-mirrors.service.d
sudo ln -sf "$CONFIG/systemd/cachyos-rate-mirrors-wait-for-network.conf" \
    /etc/systemd/system/cachyos-rate-mirrors.service.d/wait-for-network.conf
echo "    cachyos-rate-mirrors → wait-for-network drop-in symlinked"

# ── Limine ────────────────────────────────────────────────────────────────────
# CachyOS Limine stack (replaces GRUB). limine-mkinitcpio-hook regenerates
# $ESP/limine.conf on each kernel build; boot snapshots via limine-snapper-sync
# (snap-pac makes pre/post-pacman snapshots). See .docs/boot/LIMINE.md.

echo ""
echo "==> Configuring Limine bootloader..."
sudo pacman -S --needed limine limine-mkinitcpio-hook limine-snapper-sync cachyos-snapper-support

ESP="$(bootctl --print-esp-path 2>/dev/null || echo /boot/efi)"

# Sort kernel entries so linux-cachyos lists before linux-cachyos-lts.
sudo install -m 0644 "$CONFIG/limine/default-limine" /etc/default/limine
echo "    limine → /etc/default/limine installed (ENABLE_SORT)"

# Theme (Catppuccin Mocha, diegons490): wallpaper asset on the ESP + header keys.
# limine-entry-tool preserves these header keys across regeneration.
sudo cp "$CONFIG/limine/limine-splash.png" "$ESP/limine-splash.png"
if [[ -f "$ESP/limine.conf" ]] && ! sudo grep -q '^wallpaper:' "$ESP/limine.conf"; then
    sudo sed -i "/^timeout:/r $CONFIG/limine/theme.conf" "$ESP/limine.conf"
    sudo sed -i 's|^default_entry: .*|default_entry: CachyOS/linux-cachyos|' "$ESP/limine.conf"
    echo "    limine → theme + default kernel applied"
fi

if $IS_GALAXY_BOOK; then
    WARNINGS+=("limine: confirm $ESP/limine.conf cmdline carries the Galaxy Book params")
    WARNINGS+=("        (acpi_osi, mem_sleep_default=s2idle, i915.*, pcie_aspm.*).")
    WARNINGS+=("        They ride the live /proc/cmdline; on a fresh install pin them in")
    WARNINGS+=("        /etc/default/limine (KERNEL_CMDLINE[default]) — see .docs/boot/LIMINE.md")
fi

# ── intel-undervolt ───────────────────────────────────────────────────────────

if $IS_GALAXY_BOOK; then
    sudo ln -sf "$CONFIG/intel-undervolt/intel-undervolt.conf" /etc/intel-undervolt.conf
    echo "    intel-undervolt → symlinked"
elif [[ "$CPU_VENDOR" == "intel" ]]; then
    WARNINGS+=("intel-undervolt: Intel CPU detected but not a Galaxy Book — power limits")
    WARNINGS+=("      in $CONFIG/intel-undervolt/intel-undervolt.conf may not suit this CPU")
    WARNINGS+=("      Review PL1/PL2 values before linking and enabling")
else
    WARNINGS+=("intel-undervolt: skipped — $CPU_VENDOR CPU, package is Intel-only")
fi

# ── s2idle service ────────────────────────────────────────────────────────────

if $IS_GALAXY_BOOK; then
    sudo ln -sf "$CONFIG/s2idle/s2idle-optimize.service" /etc/systemd/system/s2idle-optimize.service
    sudo chmod +x "$CONFIG/s2idle/s2idle-optimize.sh"
    sudo ln -sf "$CONFIG/s2idle/s2idle-optimize.sh" /usr/local/bin/s2idle-optimize.sh
    echo "    s2idle → symlinked"
else
    WARNINGS+=("s2idle: skipped — tuned for Galaxy Book Gen4 power management")
    $IS_LAPTOP && WARNINGS+=("        Laptop detected — consider adapting for your hardware")
fi

sudo systemctl daemon-reload

# ── User services ─────────────────────────────────────────────────────────────

echo ""
echo "==> Enabling user services..."

chmod +x "$CONFIG/pkg-tracker.sh"
systemctl --user enable --now pkg-tracker.timer
systemctl --user enable --now polkit-agent.service
systemctl --user enable --now theme-watch.service
systemctl --user enable --now powerstat-logger.service

# ── Session restore (hyprflow) ─────────────────────────────────────────────────
# Autosave timer captures the window/workspace layout every 10 min; `hyprflow
# restore` (exec-once in hyprland.conf) replays it on login.
systemctl --user enable --now hyprflow-autosave.timer

# Zen is optional: hyprflow records a window's class ("zen") as its relaunch
# command, but the binary is `zen-browser`, so restore would exec a missing
# `zen`. This per-app override fixes it. Default No — skip if you don't use Zen
# (or have since moved to another browser).
read -rp "    Wire up Zen for hyprflow session restore? [y/N] " _zen
if [[ "$_zen" =~ ^[Yy]$ ]]; then
    mkdir -p "$CONFIG/hyprflow"
    if grep -q '^\[apps\.zen\]' "$CONFIG/hyprflow/config.toml" 2>/dev/null; then
        echo "    zen → already in hyprflow/config.toml, skipping"
    else
        cat >> "$CONFIG/hyprflow/config.toml" <<'ZEN'
# Zen's window class is "zen" but the binary is `zen-browser`; hyprflow captures
# the class as the launch command, so restore would exec a nonexistent `zen`.
[apps.zen]
binary = "zen-browser"
ZEN
        echo "    zen → wired up for hyprflow session restore"
    fi
else
    echo "    zen → skipped"
fi

# ── Shell (zsh + oh-my-zsh) ────────────────────────────────────────────────────

echo ""
echo "==> Setting up zsh shell..."

# Symlink .zshrc / .zshenv from the repo into $HOME (backup any pre-existing file)
for f in .zshrc .zshenv; do
    if [[ -e "$HOME/$f" && ! -L "$HOME/$f" ]]; then
        mv "$HOME/$f" "$HOME/$f.pre-config.bak"
        echo "    backed up existing ~/$f → ~/$f.pre-config.bak"
    fi
    ln -sfn "$CONFIG/$f" "$HOME/$f"
done
echo "    .zshrc, .zshenv → symlinked from repo"

# Install oh-my-zsh + powerlevel10k theme + plugins (idempotent; .aliases/.p10k.zsh
# are tracked in the repo, so only the framework needs cloning here)
ZSH_DIR="$HOME/.oh-my-zsh"
if [[ ! -d "$ZSH_DIR" ]]; then
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
    echo "    oh-my-zsh → cloned"
fi
ZSH_CUSTOM="$ZSH_DIR/custom"
clone_omz() {  # $1 = target dir, $2 = repo url
    [[ -d "$1" ]] || { git clone --depth=1 "$2" "$1"; echo "    $(basename "$1") → cloned"; }
}
clone_omz "$ZSH_CUSTOM/themes/powerlevel10k"          https://github.com/romkatv/powerlevel10k.git
clone_omz "$ZSH_CUSTOM/plugins/zsh-autosuggestions"   https://github.com/zsh-users/zsh-autosuggestions.git
clone_omz "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" https://github.com/zsh-users/zsh-syntax-highlighting.git

# Make zsh the login shell
ZSH_BIN="$(command -v zsh || true)"
if [[ -n "$ZSH_BIN" && "$(getent passwd "$(whoami)" | cut -d: -f7)" != "$ZSH_BIN" ]]; then
    if chsh -s "$ZSH_BIN"; then
        echo "    login shell → zsh"
    else
        WARNINGS+=("zsh: chsh failed — set it manually: chsh -s $ZSH_BIN")
    fi
fi

# ── Package tracker ───────────────────────────────────────────────────────────

echo ""
echo "==> Running initial package list sync..."
"$CONFIG/pkg-tracker.sh"

# ── Hardware services (Galaxy Book only) ──────────────────────────────────────

if $IS_GALAXY_BOOK; then
    echo ""
    echo "==> Enabling hardware tuning services..."
    sudo systemctl enable --now intel-undervolt
    sudo systemctl enable --now s2idle-optimize.service
fi

sudo limine-update

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "==> Done. Remaining manual steps:"
echo "    1. Place wallpaper at ~/Pictures/Wallpaper/wallpaper.png"
echo "    2. Run: ~/.config/hypr/scripts/theme-sync.sh"
echo "    3. Log out and select 'Hyprland (uwsm)' from SDDM (also activates zsh login shell)"
! $IS_LAPTOP  && echo "    4. Edit hyprland.conf — remove touchpad/lid/brightness input settings"
[[ "$GPU_VENDOR" != "intel" ]] && \
    echo "    5. Edit hyprland.conf — replace intel-media-driver env vars for $GPU_VENDOR GPU"

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo "==> Warnings (review before first boot):"
    for w in "${WARNINGS[@]}"; do
        echo "    !! $w"
    done
fi
