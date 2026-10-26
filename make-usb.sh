#!/bin/bash
# Build a macOS Sequoia USB installer with this repository's OpenCore EFI (run on a Mac).
# Usage: sudo ./make-usb.sh [-y] diskN    (find diskN with: diskutil list external; -y skips the confirmation)
# Disks larger than 64 GB are split into a 32 GB installer and an exFAT "DATA" partition.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="${PKG:-$HERE/InstallAssistant.pkg}"
APP="/Applications/Install macOS Sequoia.app"
NVRAM_ARGS='NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args'
YES=0
if [ "${1:-}" = "-y" ]; then YES=1; shift; fi
DISK="${1:-}"

die() { echo "Error: $*" >&2; exit 1; }
field() { plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null || true; }

# Installer-friendly settings for the copy on the stick only: the picker waits for you,
# boot is verbose, and OpenCore writes opencore-*.txt logs to the stick's EFI partition.
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

[ "$(id -u)" -eq 0 ] || die "run it with sudo: sudo \"$0\" diskN"
[[ "$DISK" =~ ^disk[0-9]+$ ]] || die "usage: sudo \"$0\" [-y] diskN (see: diskutil list external)"
[ -d "$HERE/EFI/OC" ] || die "EFI folder not found next to the script"
serial="$(plutil -extract PlatformInfo.Generic.SystemSerialNumber raw -o - "$HERE/EFI/OC/config.plist" 2>/dev/null || true)"
[ -n "$serial" ] || [ "${ALLOW_EMPTY_SMBIOS:-0}" = 1 ] \
    || die "EFI/OC/config.plist has no SMBIOS yet. Generate a MacBookAir8,1 serial, MLB, UUID and ROM first (see README)."

info="$(diskutil info -plist "/dev/$DISK")" || die "/dev/$DISK not found"
[ "$(field "$info" WholeDisk)" = "true" ] || die "$DISK is not a whole disk"
[ "$(field "$info" Internal)" = "false" ] || die "$DISK is an internal disk, refusing"
[ "$(field "$info" RemovableMediaOrExternalDevice)" = "true" ] || die "$DISK is not an external device"
size="$(field "$info" Size)"
[ "${size:-0}" -ge 15000000000 ] || die "the disk is smaller than 16 GB"

echo "Target: /dev/$DISK  $(field "$info" MediaName)  ~$((size / 1000000000)) GB ($(field "$info" BusProtocol))"
diskutil list "/dev/$DISK"
echo "Everything on this disk will be erased."
if [ "$YES" -ne 1 ]; then
    read -r -p "Type the disk identifier again ($DISK) to continue: " answer
    [ "$answer" = "$DISK" ] || die "cancelled, nothing was changed"
fi

echo "==> [1/5] Erasing and partitioning (GUID)"
diskutil unmountDisk "/dev/$DISK" >/dev/null 2>&1 || diskutil unmountDisk force "/dev/$DISK"
if [ "$size" -gt 64000000000 ]; then
    diskutil partitionDisk "/dev/$DISK" GPT JHFS+ SEQUOIA 32G ExFAT DATA R
else
    diskutil eraseDisk JHFS+ SEQUOIA GPT "/dev/$DISK"
fi

echo "==> [2/5] Preparing Install macOS Sequoia.app"
if [ ! -d "$APP" ]; then
    [ -f "$PKG" ] || die "neither $APP nor $PKG exists (see README for how to download the installer)"
    pkgutil --check-signature "$PKG" | grep -q "Apple Software" || die "$PKG is not signed by Apple"
    installer -pkg "$PKG" -target /
fi

echo "==> [3/5] Writing the installer (10-30 minutes)"
"$APP/Contents/Resources/createinstallmedia" --volume /Volumes/SEQUOIA --nointeraction
VOL="/Volumes/Install macOS Sequoia"
[ -d "$VOL" ] || die "$VOL not found, createinstallmedia probably failed"

echo "==> [4/5] Copying OpenCore to the stick's EFI partition"
efi="${DISK}s1"
[ "$(field "$(diskutil info -plist "$efi")" Content)" = "EFI" ] || die "$efi is not an EFI partition"
diskutil mount "$efi" >/dev/null
mnt="$(field "$(diskutil info -plist "$efi")" MountPoint)"
[ -n "$mnt" ] || die "could not mount the EFI partition"
rm -rf "$mnt/EFI"
cp -RX "$HERE/EFI" "$mnt/"
usb_tweaks "$mnt/EFI/OC/config.plist"
dot_clean -m "$mnt" 2>/dev/null || true
# Only the EFI folder: Spotlight creates .Spotlight-V100 right after mounting and it is not accessible.
find "$mnt/EFI" -name '.DS_Store' -delete 2>/dev/null || true
diskutil unmount "$efi" >/dev/null

echo "==> [5/5] Copying post-install files to $VOL/PostInstall"
rm -rf "$VOL/PostInstall"
mkdir -p "$VOL/PostInstall"
cp -RX "$HERE/EFI" "$VOL/PostInstall/"
for f in install-efi-internal.sh README.md README.en.md LICENSE HeliPort.dmg; do
    if [ -e "$HERE/$f" ]; then cp -X "$HERE/$f" "$VOL/PostInstall/"; fi
done

echo "Done. Eject with: diskutil eject /dev/$DISK"
