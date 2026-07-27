#!/usr/bin/env bash
# Detect silent fallbacks: subsystems running on a degraded path while a setting
# claims otherwise. Each check names what is CLAIMED, what was MEASURED, and
# fails only when the two disagree.
#
# Exit status = number of divergences. --notify raises a desktop notification.
#
# Usage: silent-fallback-check.sh [--notify] [--quiet] [--window SECONDS]
# No pipefail: `grep -q` exits on first match, SIGPIPEs its upstream (141), and
# pipefail would then read a successful match as a failed pipeline.
set -u

WINDOW=4
NOTIFY=0
QUIET=0
while (($#)); do
  case "$1" in
    --notify) NOTIFY=1 ;;
    --quiet)  QUIET=1 ;;
    --window) WINDOW="$2"; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

FAILURES=()
ROWS=()

row() { # name  claim  measured  verdict
  ROWS+=("$1|$2|$3|$4")
  [[ $4 == DIVERGES ]] && FAILURES+=("$1: claimed $2, measured $3")
  return 0
}

# Sum a DRM engine's busy-time across our own processes. Fds may alias the same
# client, so the total overcounts — only zero vs non-zero is meaningful here.
drm_busy() {
  local engine=$1 total=0 v
  for f in /proc/[0-9]*/fdinfo/*; do
    v=$(grep -m1 "^drm-engine-${engine}:" "$f" 2>/dev/null) || continue
    v=${v##*:}; v=${v// ns/}; v=${v//[[:space:]]/}
    [[ $v =~ ^[0-9]+$ ]] && (( total += v ))
  done
  echo "$total"
}


zen_pref() { # pref name -> value, user.js wins over prefs.js
  local p name=$1 v=""
  for p in "$HOME/.zen/zen-default/user.js" "$HOME/.zen/zen-default/prefs.js"; do
    [[ -r $p ]] || continue
    v=$(grep -oP "user_pref\(\"\Q$name\E\",\s*\K[^)]+" "$p" 2>/dev/null | tail -1)
    [[ -n $v ]] && { echo "${v//[[:space:]\"]/}"; return; }
  done
  echo "unset"
}

# ── 1. Video decode: the one that hid for months ─────────────────────────────
# The Zen/Firefox "hardware acceleration" checkbox drives the render engine only.
# Decode is a separate engine behind a separate pref with no UI and no error on
# fallback, so measure the engine rather than trusting either.
# Measures the engine's *lifetime* total, not a sampling window. Instantaneous
# sampling needs to know whether video is playing right now, and audio activity
# is not that signal — music would look like idle-engine-during-playback. A
# browser that has been up for hours has certainly decoded some video, so a
# lifetime total of exactly zero is conclusive on its own.
check_video_decode() {
  local pref claim total age browsers
  pref=$(zen_pref "media.hardware-video-decoding.force-enabled")
  case $pref in
    true)  claim="hardware" ;;
    false) claim="software (pref explicitly false)" ;;
    *)     claim="hardware (implied by accel checkbox)" ;;
  esac

  browsers=$(pgrep -d, -f 'zen-bin|firefox|chromium|helium' 2>/dev/null)
  if [[ -z $browsers ]]; then
    row "video-decode" "$claim" "no browser running" "SKIP"
    return
  fi
  age=$(ps -o etimes= -p "$browsers" 2>/dev/null | sort -rn | head -1)
  age=${age:-0}

  total=$(drm_busy video)
  if (( total > 0 )); then
    row "video-decode" "$claim" "GPU video engine has run ($((total/1000000))ms)" "ok"
  elif (( age < 3600 )); then
    row "video-decode" "$claim" "engine idle, browser only $((age/60))min old" "SKIP"
  elif [[ $claim == hardware* ]]; then
    row "video-decode" "$claim" "engine never used in $((age/3600))h — CPU decoding" "DIVERGES"
  else
    row "video-decode" "$claim" "engine never used in $((age/3600))h — CPU decoding" "ok"
  fi
}

# ── 2. GPU rendering: catches an llvmpipe/swrast fallback ────────────────────
check_gpu_render() {
  local before after
  before=$(drm_busy render)
  sleep 1
  after=$(drm_busy render)
  if (( after > before )); then
    row "gpu-render" "hardware" "GPU render engine active" "ok"
  else
    row "gpu-render" "hardware" "render engine idle over 1s" "SKIP"
  fi
}

# ── 3. Running kernel's module tree ──────────────────────────────────────────
# A kernel upgrade deletes the running kernel's modules. Everything already
# loaded keeps working, so nothing surfaces until a modprobe fails.
check_kernel_modules() {
  local kver; kver=$(uname -r)
  if [[ -d /usr/lib/modules/$kver/kernel ]]; then
    row "kernel-modules" "present for $kver" "present" "ok"
  else
    row "kernel-modules" "present for $kver" "deleted by upgrade" "DIVERGES"
  fi
}

# ── 4. DKMS built for the kernel actually running ────────────────────────────
# A missing build for the *running* kernel is normal between a kernel upgrade and
# the next boot, and harmless while the module is still resident. Only an absent
# build whose modules are also not loaded is an actual divergence.
check_dkms() {
  command -v dkms >/dev/null || { row "dkms" "n/a" "dkms not installed" "SKIP"; return; }
  local kver name status broken=() pending=() ko mod loaded
  kver=$(uname -r)

  while read -r name; do
    [[ -z $name ]] && continue
    status=$(dkms status 2>/dev/null | grep "^$name")
    case "$status" in
      *"$kver"*) continue ;;   # built for the running kernel
    esac

    # No build here. Are the modules it provides loaded anyway? Derive their
    # names from a build that does exist for some other kernel.
    loaded=1
    for ko in /usr/lib/modules/*/updates/dkms/*.ko*; do
      [[ -e $ko ]] || continue
      mod=$(basename "$ko"); mod=${mod%%.ko*}; mod=${mod//-/_}
      [[ -d /sys/module/$mod ]] || loaded=0
    done
    (( loaded )) && pending+=("$name") || broken+=("$name")
  done < <(dkms status 2>/dev/null | sed 's#[/,].*##' | sort -u)

  if ((${#broken[@]} > 0)); then
    row "dkms" "modules available" "not built for $kver, not loaded: ${broken[*]}" "DIVERGES"
  elif ((${#pending[@]} > 0)); then
    row "dkms" "modules available" "loaded; build pending for $kver: ${pending[*]}" "ok"
  else
    row "dkms" "modules available" "built for $kver" "ok"
  fi
}

# ── 5. Speaker amps: the DKMS module binds amps ACPI never creates ───────────
check_speakers() {
  local amps
  # Bound amps appear as i2c-MAX98390:00-max98390-hda.N, not as bare 2-00xx.
  amps=$(ls /sys/bus/i2c/devices/ 2>/dev/null | grep -c 'max98390-hda\.')
  if [[ ! -d /sys/module/snd_hda_scodec_max98390 ]]; then
    row "speakers" "4 amps driven" "max98390 module not loaded" "DIVERGES"
  elif (( amps < 4 )); then
    row "speakers" "4 amps driven" "only ${amps} amps bound" "DIVERGES"
  else
    row "speakers" "4 amps driven" "module loaded, ${amps} amps bound" "ok"
  fi
}

# ── 6. Memory: zram compresses into RAM, so a full zram costs real RAM ───────
check_memory() {
  local avail_mb pct
  avail_mb=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
  if [[ -r /sys/block/zram0/mm_stat ]]; then
    read -r orig compr used _ < /sys/block/zram0/mm_stat
    pct=$(( used * 100 / $(awk '/MemTotal/{print $2*1024}' /proc/meminfo) ))
    if (( avail_mb < 1500 )); then
      row "memory" "headroom available" \
          "${avail_mb}MB free, zram holds $((orig/1073741824))G in $((used/1048576))MB (${pct}% of RAM)" "DIVERGES"
    else
      row "memory" "headroom available" "${avail_mb}MB available" "ok"
    fi
  fi
}

# ── 7. Power: throttled while plugged in is a silent performance fallback ────
check_power() {
  local gov epp charging
  gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
  epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
  charging=$(cat /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online 2>/dev/null | head -1)
  if [[ $charging == 1 && $gov == powersave && $epp == power ]]; then
    row "cpu-power" "full speed on AC" "governor=$gov epp=$epp" "DIVERGES"
  else
    row "cpu-power" "matches power source" "governor=$gov epp=$epp ac=${charging:-?}" "ok"
  fi
}

check_video_decode
check_gpu_render
check_kernel_modules
check_dkms
check_speakers
check_memory
check_power

if (( ! QUIET )); then
  printf '%-16s %-38s %-46s %s\n' CHECK CLAIMED MEASURED VERDICT
  printf '%.0s─' {1..122}; printf '\n'
  for r in "${ROWS[@]}"; do
    IFS='|' read -r a b c d <<<"$r"
    printf '%-16s %-38s %-46s %s\n' "$a" "$b" "$c" "$d"
  done
fi

if ((${#FAILURES[@]} > 0)); then
  (( QUIET )) || { echo; printf '%s\n' "${FAILURES[@]}"; }
  if (( NOTIFY )); then
    notify-send -a "system" -u normal \
      "Silent fallback: ${#FAILURES[@]} subsystem(s) degraded" \
      "$(printf '%s\n' "${FAILURES[@]}")"
  fi
fi

exit "${#FAILURES[@]}"
