#!/bin/bash
# Run on the Surface in macOS: add (or update) one kext from this repository in the OpenCore EFI
# on the internal disk and enable it, leaving the rest of that EFI, including your SMBIOS, as is.
# Usage: sudo bash ./add-kext-internal.sh IntelHIDButtons
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-}"
REPO_CFG="$HERE/EFI/OC/config.plist"

die() { echo "Error: $*" >&2; exit 1; }
field() { plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null || true; }
list() { plutil -extract "$2" json -o - - <<<"$1" 2>/dev/null | tr -d '[]"' | tr ',' ' '; }

# Print the index of the Kernel.Add entry whose BundlePath is $2 in config $1, if any.
entry_index() {
    local i=0 path
    while path="$(plutil -extract "Kernel.Add.$i.BundlePath" raw -o - "$1" 2>/dev/null)"; do
        if [ "$path" = "$2" ]; then echo "$i"; return; fi
        i=$((i + 1))
    done
}

# TARGET_EFI points at an already mounted EFI volume instead (used for testing).
[ -n "${TARGET_EFI:-}" ] || [ "$(id -u)" -eq 0 ] || die "run it with sudo: sudo bash \"$0\" KextName"
[ -n "$NAME" ] && [ -d "$HERE/EFI/OC/Kexts/$NAME.kext" ] || die "usage: sudo bash \"$0\" KextName (a kext in EFI/OC/Kexts)"
src="$(entry_index "$REPO_CFG" "$NAME.kext")"
[ -n "$src" ] || die "$NAME.kext has no Kernel -> Add entry in $REPO_CFG"

efi=""
if [ -n "${TARGET_EFI:-}" ]; then
    mnt="$TARGET_EFI"
else
    echo "==> [1/4] Finding the internal disk's EFI partition"
    for d in $(list "$(diskutil list -plist internal physical)" WholeDisks); do
        for p in $(list "$(diskutil list -plist "$d")" AllDisks); do
            if [ "$(field "$(diskutil info -plist "$p")" Content)" = "EFI" ]; then
                efi="$p"
                break 2
            fi
        done
    done
    [ -n "$efi" ] || die "no EFI partition found on the internal disk"
    diskutil mount "$efi" >/dev/null
    mnt="$(field "$(diskutil info -plist "$efi")" MountPoint)"
    [ -n "$mnt" ] || die "could not mount $efi"
    echo "  $efi at $mnt"
fi
cfg="$mnt/EFI/OC/config.plist"
[ -f "$cfg" ] || die "no OpenCore config.plist in $mnt/EFI/OC"

echo "==> [2/4] Backing up config.plist"
owner="${SUDO_USER:-$(id -un)}"
home="$(dscl . -read "/Users/$owner" NFSHomeDirectory | awk '{print $2}')"
bak="$home/config-backup-$(date +%Y%m%d-%H%M%S).plist"
cp "$cfg" "$bak"
chown "$owner" "$bak"
echo "  $bak"

echo "==> [3/4] Copying $NAME.kext"
rm -rf "$mnt/EFI/OC/Kexts/$NAME.kext"
cp -RX "$HERE/EFI/OC/Kexts/$NAME.kext" "$mnt/EFI/OC/Kexts/"
dot_clean -m "$mnt/EFI/OC/Kexts" 2>/dev/null || true

echo "==> [4/4] Enabling it in config.plist"
entry="$(plutil -extract "Kernel.Add.$src" xml1 -o - "$REPO_CFG" | sed -n '/^<dict>/,/^<\/dict>/p')"
dst="$(entry_index "$cfg" "$NAME.kext")"
if [ -n "$dst" ]; then
    # plutil -replace on an array index inserts, so remove the old entry and insert in its place.
    plutil -remove "Kernel.Add.$dst" "$cfg"
    plutil -insert "Kernel.Add.$dst" -xml "$entry" "$cfg"
else
    plutil -insert Kernel.Add -xml "$entry" -append "$cfg"
    dst="$(entry_index "$cfg" "$NAME.kext")"
fi
plutil -replace "Kernel.Add.$dst.Enabled" -bool true "$cfg"
plutil -lint -s "$cfg"
[ -z "$efi" ] || diskutil unmount "$efi" >/dev/null

echo "Done, reboot to use it. To undo, copy $bak back to EFI/OC/config.plist on the internal EFI partition."
