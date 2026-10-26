#!/bin/bash
# Run on the Surface in macOS: install the EFI next to this script on the internal disk's
# EFI partition, after backing up the current one to your home folder.
# Usage: sudo "/Volumes/Install macOS Sequoia/PostInstall/install-efi-internal.sh"
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

die() { echo "Error: $*" >&2; exit 1; }
field() { plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null || true; }
list() { plutil -extract "$2" json -o - - <<<"$1" 2>/dev/null | tr -d '[]"' | tr ',' ' '; }

[ "$(id -u)" -eq 0 ] || die "run it with sudo: sudo \"$0\""
[ -d "$HERE/EFI/OC" ] && [ -f "$HERE/EFI/BOOT/BOOTx64.efi" ] || die "$HERE/EFI not found"
serial="$(plutil -extract PlatformInfo.Generic.SystemSerialNumber raw -o - "$HERE/EFI/OC/config.plist" 2>/dev/null || true)"
[ -n "$serial" ] || [ "${ALLOW_EMPTY_SMBIOS:-0}" = 1 ] || die "this EFI has no SMBIOS (serial, MLB, UUID, ROM), see README"

echo "==> [1/4] Finding the internal disk's EFI partition"
efi=""
for d in $(list "$(diskutil list -plist internal physical)" WholeDisks); do
    for p in $(list "$(diskutil list -plist "$d")" AllDisks); do
        if [ "$(field "$(diskutil info -plist "$p")" Content)" = "EFI" ]; then
            efi="$p"
            break 2
        fi
    done
done
[ -n "$efi" ] || die "no EFI partition found on the internal disk"
echo "  $efi"
diskutil mount "$efi" >/dev/null
mnt="$(field "$(diskutil info -plist "$efi")" MountPoint)"
[ -n "$mnt" ] || die "could not mount the EFI partition"

echo "==> [2/4] Backing up the current EFI"
owner="${SUDO_USER:-root}"
home="$(dscl . -read "/Users/$owner" NFSHomeDirectory | awk '{print $2}')"
if [ -d "$mnt/EFI/OC" ]; then
    bak="$home/EFI-backup-$(date +%Y%m%d-%H%M%S)"
    cp -R "$mnt/EFI" "$bak"
    chown -R "$owner" "$bak"
    echo "  saved to $bak"
else
    echo "  no OpenCore on the internal disk yet, nothing to back up"
fi

echo "==> [3/4] Installing the new EFI"
mkdir -p "$mnt/EFI/BOOT"
rm -rf "$mnt/EFI/OC"
cp -RX "$HERE/EFI/OC" "$mnt/EFI/"
cp -RX "$HERE/EFI/BOOT/." "$mnt/EFI/BOOT/"
dot_clean -m "$mnt" 2>/dev/null || true
find "$mnt/EFI" -name '.DS_Store' -delete 2>/dev/null || true

echo "==> [4/4] Verifying"
diff -rq "$HERE/EFI/OC" "$mnt/EFI/OC" && echo "  matches the new EFI"
diskutil unmount "$efi" >/dev/null
echo "Done, reboot to use it."
