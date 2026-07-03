#!/usr/bin/env bash
# Read-only pre-flight conflict scan for ~/.config/pkglist.txt (no build, no sudo).
cd ~/.config || exit 1
mapfile -t PKGS < <(grep -vE '^\s*$' pkglist.txt)
declare -A INPKG; for p in "${PKGS[@]}"; do INPKG[$p]=1; done
declare -A INST;  while read -r p; do INST[$p]=1; done < <(pacman -Qq)
strip() { echo "${1%%[<>=:]*}"; }

echo "packages in list: ${#PKGS[@]}   installed on system: ${#INST[@]}"
echo

echo "===== A. candidate DECLARES conflict/replaces with an INSTALLED pkg ====="
{
  pacman -Sii "${PKGS[@]}" 2>/dev/null
  for p in "${PKGS[@]}"; do
    pacman -Sp "$p" &>/dev/null && continue          # repo pkg, handled above
    f=$(ls -t ~/.cache/yay/"$p"/*.pkg.tar.zst 2>/dev/null | head -1)
    [ -n "$f" ] && pacman -Qip "$f" 2>/dev/null
  done
} | awk '
  /^Name +:/        {name=$3}
  /^Conflicts With/ {sub(/^[^:]*: /,""); print "conflicts\t" name "\t" $0}
  /^Replaces/       {sub(/^[^:]*: /,""); print "replaces\t"  name "\t" $0}
' | while IFS=$'\t' read -r kind name targets; do
    [ "$targets" = "None" ] && continue
    [ -n "${INST[$name]}" ] && continue          # candidate already installed -> --needed skips it
    for t in $targets; do
      raw="$t"; t=$(strip "$t")
      [ -n "${INST[$t]}" ] || continue
      # version-constrained conflict (e.g. mkinitcpio<38): test the INSTALLED version against it
      if [[ "$raw" == *[\<\>=]* ]]; then
        # pacman -T "$raw" exits 0 iff the installed version satisfies the conflict range (=> REAL).
        pacman -T "$raw" &>/dev/null || continue   # not in range -> safe, skip
      fi
      echo "  ⟂ $name $kind INSTALLED '$t'"
    done
  done | sort -u

echo
echo "===== B. an INSTALLED pkg DECLARES a conflict with a NEW candidate ====="
pacman -Qi 2>/dev/null | awk '
  /^Name +:/        {name=$3}
  /^Conflicts With/ {sub(/^[^:]*: /,""); print name "\t" $0}
' | while IFS=$'\t' read -r name targets; do
    [ "$targets" = "None" ] && continue
    for t in $targets; do
      t=$(strip "$t")
      [ -n "${INPKG[$t]}" ] && [ -z "${INST[$t]}" ] && echo "  ⟂ candidate '$t' conflicts INSTALLED '$name'"
    done
  done | sort -u

echo
echo "===== C. -git/-bin variant whose base pkg is already installed ====="
for p in "${PKGS[@]}"; do
  base=${p%-git}; base=${base%-bin}
  [ "$base" != "$p" ] && [ -n "${INST[$base]}" ] && echo "  ⟂ $p  (base '$base' already installed)"
done

echo
echo "===== scan complete ====="
