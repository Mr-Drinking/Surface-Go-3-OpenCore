#!/bin/bash
# After editing EFI/, refresh the OpenCore copy on an existing installer stick (run on a Mac),
# and pull the stick's OpenCore logs and panic reports into logs/.
# Usage: sudo ./update-usb-efi.sh diskN    (find diskN with: diskutil list external)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NVRAM_ARGS='NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args'
DISK="${1:-}"

die() { echo "Error: $*" >&2; exit 1; }
field() { plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null || true; }

# Same installer-friendly settings as make-usb.sh, applied to the stick's copy only.
usb_tweaks() {
    local cfg="$1" args
    args="$(plutil -extract "$NVRAM_ARGS" raw -o - "$cfg")"
    for a in -v keepsyms=1 debug=0x100; do
        case " $args " in *" $a "*) ;; *) args="$args $a" ;; esac
    done
    plutil -replace "$NVRAM_ARGS" -string "$args" "$cfg"
    plutil -replace Misc.Boot.Timeout -integer 0 "$cfg"
    plutil -replace Misc.Debug.Target -integer 67 "$cfg"
    plutil -replace Misc.Debug.DisableWatchDog -bool true "$cfg"
    plutil -replace Misc.Debug.AppleDebug -bool true "$cfg"
    plutil -replace Misc.Debug.ApplePanic -bool true "$cfg"
}

rebuild_efi() {
    echo "  Recreating the EFI partition's file system (it only holds OpenCore, which is copied back next)"
    diskutil unmount "$efi" >/dev/null 2>&1 || true
    newfs_msdos -F 32 -v EFI "/dev/r$efi"
    diskutil mount "$efi" >/dev/null
}

[ "$(id -u)" -eq 0 ] || die "run it with sudo: sudo \"$0\" diskN"
[[ "$DISK" =~ ^disk[0-9]+$ ]] || die "usage: sudo \"$0\" diskN (see: diskutil list external)"
[ -d "$HERE/EFI/OC" ] || die "EFI folder not found next to the script"
info="$(diskutil info -plist "/dev/$DISK")" || die "/dev/$DISK not found"
[ "$(field "$info" Internal)" = "false" ] || die "$DISK is an internal disk, refusing"
efi="${DISK}s1"
[ "$(field "$(diskutil info -plist "$efi")" Content)" = "EFI" ] || die "$efi is not an EFI partition"

echo "==> [1/4] Read-only check of the EFI partition's file system"
fs_ok=1
fsck_msdos -n "/dev/r$efi" || fs_ok=0

echo "==> [2/4] Mounting the EFI partition"
diskutil mount "$efi" >/dev/null 2>&1 || rebuild_efi
mnt="$(field "$(diskutil info -plist "$efi")" MountPoint)"
[ -n "$mnt" ] || die "could not mount the EFI partition"

echo "==> [3/4] Copying OpenCore logs and panic reports to logs/"
logs="$HERE/logs"
mkdir -p "$logs"
found=0
for f in "$mnt"/opencore-*.txt "$mnt"/panic-*.txt; do
    [ -e "$f" ] || continue
    cp -X "$f" "$logs/"
    found=1
    echo "  $(basename "$f")"
done
[ "$found" -eq 1 ] || echo "  no log files"
chown -R "${SUDO_USER:-root}" "$logs"
[ "$fs_ok" -eq 1 ] || rebuild_efi

echo "==> [4/4] Replacing the stick's EFI"
rm -rf "$mnt/EFI"
cp -RX "$HERE/EFI" "$mnt/"
usb_tweaks "$mnt/EFI/OC/config.plist"
dot_clean -m "$mnt" 2>/dev/null || true
find "$mnt/EFI" -name '.DS_Store' -delete 2>/dev/null || true
diff -rq -x config.plist "$HERE/EFI" "$mnt/EFI" && echo "  EFI matches this repository (config.plist has the installer tweaks)"
diskutil unmount "$efi" >/dev/null
echo "Done."
