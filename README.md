# Surface-Go-3-OpenCore

OpenCore EFI for the **Microsoft Surface Go 3 (Pentium Gold 6500Y)** running **macOS Sequoia**, including a fix for the battery status that other Surface Go 3 EFIs are missing.

[中文说明](README.zh-CN.md)

| | |
| --- | --- |
| Tested on | Surface Go 3, Pentium Gold 6500Y, 8 GB RAM, 128 GB NVMe SSD |
| macOS | Sequoia 15.8.1 (24H32) |
| OpenCore | MOD 1.0.7 ([OpenCore_NO_ACPI build](https://github.com/wjz304/OpenCore_NO_ACPI_Build)) |
| SMBIOS | MacBookAir8,1 (with `-no_compat_check` and `revpatch=sbvmm`) |
| Based on | [jlempen/Surface-Go-2-OpenCore](https://github.com/jlempen/Surface-Go-2-OpenCore) (commit `4fbf739`) |

The Surface Go 3 is a Surface Go 2 with new CPUs: same chassis, display, Intel AX200 Wi-Fi, card reader and Type Cover. The Pentium Gold 6500Y runs at the same clocks as the Go 2's Core m3-8100Y, has the same UHD 615 iGPU (`0x591C`), and, unlike the Go 2's Pentium 4425Y, supports AVX2, which macOS Ventura and later require. The Core i3-10100Y model is untested. The 64 GB eMMC model is not supported because macOS has no eMMC driver.

## Status

**Verified on the tested machine**

- Installing macOS Sequoia and booting from the internal SSD
- Battery percentage and the Battery pane in System Settings (with the fix below)
- Wi-Fi with `itlwm` and [HeliPort](https://github.com/OpenIntelWireless/HeliPort/releases)
- Bluetooth
- Touchscreen
- Sound (ALC298, layout-id 69)
- Power button and volume buttons with `IntelHIDButtons.kext`; the power button behaves like a Mac's (see [Volume and power buttons](#volume-and-power-buttons))

**Expected to work (works on the Go 2 with the upstream EFI, not yet confirmed on a Go 3)**

- iGPU acceleration, brightness control
- Surface Pen
- Type Cover keyboard and multi-touch trackpad
- Microphone and headphone jack
- USB-C (including display output), microSD reader
- Hibernation (`hibernatemode 25`)

**Not working**

- Front, rear and IR cameras (Intel IPU3, no macOS driver), NFC, automatic rotation
- Sleep: use hibernation instead, which resumes in about 10 seconds
- AirDrop, Handoff, Sidecar and other features that need an Apple-compatible Broadcom card

## What is different from the Surface Go 2 EFI

1. **Battery fix.** The Go 3 firmware names its battery `\_SB.BAT1` with `_HID "MSHW0146"` instead of the standard `PNP0C0A` used on the Go 2, so VirtualSMC's SMCBatteryManager never finds it. A DSDT patch renames that `_HID` to `XHID` (find `5F4849440D4D5348573031343600`, replace `584849440D4D5348573031343600`), and `SSDT-BAT1-SGO3.aml` gives the device the standard `PNP0C0A` ID. If the rename ever stops matching after a firmware update, the SSDT adds `PNP0C0A` as a compatible ID instead. The battery methods themselves read EC fields like on the Go 2, so ECEnabler and SMCBatteryManager handle the rest. Source: [`ACPI-src/SSDT-BAT1-SGO3.dsl`](ACPI-src/SSDT-BAT1-SGO3.dsl).
2. **Battery pane.** The upstream FACP patch that sets the PM profile to Mobile matches the Go 2's ACPI enable values (`A0 A1`); the Go 3 uses `F0 F1`. A Go 3 version of the patch is added (find `00080900B2000000F0F1`, replace `00020900B2000000F0F1`).
3. **Wi-Fi uses `itlwm` + HeliPort**, which works right after installation without root patches, so **SIP stays fully enabled** (`csr-active-config = 00000000`). The AirportItlwm route and its kexts are not included (see [Optional: native Wi-Fi menu](#optional-native-wi-fi-menu)).
4. **The upstream `setup_var` tools are removed.** They write CFG Lock, VT-d and DVMT variables at offsets taken from the Go 2 firmware; running them on a Go 3 could leave it unbootable. CFG Lock is handled by the `AppleXcpmCfgLock` quirk and DVMT by framebuffer patches instead.
5. Kexts that only load on Ventura or Sonoma are removed.
6. SMBIOS fields are empty. **Generate your own** before booting (see below).
7. **Volume and power buttons** through `IntelHIDButtons.kext`, a small kext written for the Go 3 (see [Volume and power buttons](#volume-and-power-buttons)).

## Installation

You need a Mac to build the installer with these scripts, a USB drive of at least 16 GB (everything on it is erased), and a Type Cover or USB keyboard: the OpenCore picker cannot be used with the touchscreen.

### 1. Generate your SMBIOS

Generate a MacBookAir8,1 serial number and MLB with [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS), or with `macserial` from the [OpenCorePkg release](https://github.com/acidanthera/OpenCorePkg/releases):

```bash
./macserial -m MacBookAir8,1 -g -n 1
```

Then fill them in (or edit `PlatformInfo → Generic` with [ProperTree](https://github.com/corpnewt/ProperTree)):

```bash
plutil -replace PlatformInfo.Generic.SystemSerialNumber -string "YOUR_SERIAL" EFI/OC/config.plist
plutil -replace PlatformInfo.Generic.MLB -string "YOUR_MLB" EFI/OC/config.plist
plutil -replace PlatformInfo.Generic.SystemUUID -string "$(uuidgen)" EFI/OC/config.plist
plutil -replace PlatformInfo.Generic.ROM -data "$(openssl rand -base64 6)" EFI/OC/config.plist
```

Never publish a `config.plist` that contains your serial numbers.

### 2. Get the macOS Sequoia installer

On a Mac that can run Sequoia: `softwareupdate --fetch-full-installer --full-installer-version 15.8.1`.
Newer Macs may not offer Sequoia there. In that case, download Sequoia's `InstallAssistant.pkg` from Apple's software update catalog with a tool such as [Mist](https://github.com/ninxsoft/Mist) or [gibMacOS](https://github.com/corpnewt/gibMacOS), and put it next to `make-usb.sh`.

Optionally put [HeliPort.dmg](https://github.com/OpenIntelWireless/HeliPort/releases) next to `make-usb.sh` as well, so it is on the stick when the Surface has no Wi-Fi yet.

### 3. Build the USB installer

```bash
diskutil list external
sudo ./make-usb.sh disk4
```

Replace `disk4` with your drive. The script erases the drive, writes the full (offline) installer, copies OpenCore to the drive's EFI partition, and puts this EFI plus `install-efi-internal.sh` in a `PostInstall` folder on the installer volume. Drives larger than 64 GB get a 32 GB installer partition and an exFAT `DATA` partition.

The copy on the stick is set up for installing: the picker waits for your choice, boot is verbose, and OpenCore writes an `opencore-*.txt` log to the stick's EFI partition on every boot.

### 4. Prepare the Surface

In Windows: back up your files, note the serial number printed under the kickstand (you need it to download the [Surface recovery image](https://support.microsoft.com/surface-recovery-image) if you ever go back), and optionally save your [BitLocker recovery key](https://aka.ms/myrecoverykey).

In the Surface UEFI (shut down, hold **Volume Up**, press Power):

- Security → Secure Boot → Change configuration → **None**. A red bar at the top of the boot screen is normal from now on.
- Boot configuration: move **USB Storage** to the top.

### 5. Install

1. Connect the Type Cover, the USB drive and the charger, then power on. To force booting from USB, hold **Volume Down** while pressing Power.
2. In the OpenCore picker, choose **Install macOS Sequoia**.
3. In Disk Utility, choose View → Show All Devices, select the top-level internal SSD (~128 GB) and erase it as **APFS** with the **GUID Partition Map**. This deletes Windows.
4. Install macOS to that disk. On each reboot choose **macOS Installer** in the picker until it disappears, then your disk. Keep the USB drive connected.
5. In Setup Assistant, skip the network and the Apple Account for now, and leave FileVault off.

### 6. After installing

1. Install HeliPort from `PostInstall` (or from its release page), connect to Wi-Fi, and enable Launch at Login.
2. Install OpenCore on the internal disk. The script finds the internal EFI partition and backs up anything already there to `~/EFI-backup-<date>`:

   ```bash
   sudo "/Volumes/Install macOS Sequoia/PostInstall/install-efi-internal.sh"
   ```

3. Unplug the USB drive and reboot to confirm the Surface boots on its own.
4. Use hibernation instead of sleep:

   ```bash
   sudo pmset restoredefaults
   sudo pmset -a hibernatemode 25
   ```

5. For proper HiDPI scaling, run [one-key-hidpi](https://github.com/jlempen/one-key-hidpi) and choose `(4) 1920x1280 Display`.
6. If Bluetooth does not reconnect after hibernation, install [Bluesnooze](https://github.com/odlp/bluesnooze).

## Troubleshooting

- **It keeps booting Windows.** No red bar at boot means Secure Boot is still on. If you copied `EFI/` to a stick by hand instead of using `make-usb.sh`, the picker boots its default entry (Windows) after 5 seconds, so press an arrow key in time. You can also boot the stick from Windows (Settings → System → Recovery → Advanced startup → Use a device). Avoid USB hubs; some enclosures are not detected by the firmware at boot.
- **Read the boot logs.** Connect the stick to your Mac and run `sudo ./update-usb-efi.sh diskN`. It copies `opencore-*.txt` and panic reports into `logs/` and refreshes the stick's EFI. If no log was written, OpenCore never ran.
- **Reset NVRAM** from the picker (press Space to show auxiliary entries).

## Volume and power buttons

**Why they need a kext.** The Go 3 firmware reports the volume buttons only to the Intel HID device (`INT33D5`, `\_SB.HIDD`): the EC queries `_QD1`–`_QD4` send it the notifications `0xC4`–`0xC7` (volume up / down, press / release). macOS has no driver for that device. The Go 2 only uses that path after Windows' Intel HID driver enables it, and otherwise falls back to an emulated PS/2 keyboard (`PS2K`) that VoodooPS2 handles; the Go 3 has no `PS2K` at all. YogaSMC's YogaHIDD understands these events but can only send keys through VoodooPS2.

**What `IntelHIDButtons.kext` does.** It attaches to `INT33D5`, tells the firmware a buttons driver is loaded (`BTNL`, then `HDSM` and `BTNE`), and turns `0xC4`–`0xC7` into the volume keys through its own virtual keyboard. `BTNL` also moves the power button to this device (`0xCE` press, `0xCF` release), so the kext sends it as the Mac power key with the real press duration and macOS applies its usual power button behavior: hold it about 1.5 seconds to sleep, or press Control–power for the restart, sleep or shut down dialog. Version 1.0.0 forwarded the press with `IOPMrootDomain::receivePowerNotification`, which macOS ignores while the system is running, so a short press did nothing. Source and build script: [`Kexts-src/IntelHIDButtons`](Kexts-src/IntelHIDButtons) (Command Line Tools and [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK), no Xcode needed).

**Add or update it on an existing installation.** The kext is included and enabled in `EFI/`. To add it to an EFI you installed earlier, or to update it, run in Terminal on the Surface with Wi-Fi working (it backs up your `config.plist` first and keeps your SMBIOS):

```bash
cd ~/Downloads
curl -L -o Surface-Go-3-OpenCore.zip https://github.com/Mr-Drinking/Surface-Go-3-OpenCore/archive/refs/heads/main.zip
unzip -q -o Surface-Go-3-OpenCore.zip
sudo bash Surface-Go-3-OpenCore-main/add-kext-internal.sh IntelHIDButtons
```

Unplug the USB installer and reboot. `ioreg -rc IntelHIDButtons | grep -E 'DSMFunctions|ButtonCaps'` shows whether the kext is running.

**Undo.** If the Surface does not boot, boot the USB installer (hold Volume Down), then restore the backup the script printed:

```bash
sudo diskutil mount disk0s1
sudo cp ~/config-backup-YYYYMMDD-HHMMSS.plist /Volumes/EFI/EFI/OC/config.plist
```

## Optional: native Wi-Fi menu

AirportItlwm gives you the native Wi-Fi menu, but on Sequoia it needs Apple's `IOSkywalkFamily.kext` and `IO80211FamilyLegacy.kext` from older macOS releases, plus `AMFIPass.kext`, SIP partially disabled (`csr-active-config = 03080000`) and a root patch with [OCLP-Mod](https://github.com/laobamac/OCLP-Mod/releases) after every macOS update. Those Apple binaries are not redistributed here; [jlempen/Surface-Go-2-OpenCore](https://github.com/jlempen/Surface-Go-2-OpenCore) has the kexts and instructions.

## Expectations

The Pentium Gold 6500Y scores roughly 900–1050 single-core and 1750–1850 multi-core in Geekbench 6, about the level of a 2018 MacBook Air, without a fan. Everyday browsing, documents and video are fine, but Windows 11 is smoother on this hardware and has sleep, cameras and a touch-friendly interface. Expect about 5 hours of battery life (figure from the Go 2).

## Credits

- [jlempen](https://github.com/jlempen/Surface-Go-2-OpenCore) and [kingo132](https://github.com/kingo132/surface-go2-hackintosh) for the Surface Go 2 EFI this is based on
- [acidanthera](https://github.com/acidanthera) for OpenCore, Lilu, VirtualSMC, WhateverGreen, AppleALC, NVMeFix, RestrictEvents, HibernationFixup, CPUFriend, BrcmPatchRAM (BlueToolFixup) and VoodooPS2, and [btwise](https://gitee.com/btwise/OpenCore_NO_ACPI) / [wjz304](https://github.com/wjz304/OpenCore_NO_ACPI_Build) for the OpenCore_NO_ACPI build
- [OpenIntelWireless](https://github.com/OpenIntelWireless) for itlwm, IntelBluetoothFirmware and HeliPort
- [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C), [ECEnabler](https://github.com/1Revenger1/ECEnabler), [RealtekCardReader](https://github.com/0xFireWolf/RealtekCardReader) / [RealtekCardReaderFriend](https://github.com/0xFireWolf/RealtekCardReaderFriend), [VoltageShift](https://github.com/sicreative/VoltageShift)
- [linux-surface](https://github.com/linux-surface/acpidumps) for the Surface Go 3 ACPI dumps that made the battery and volume button fixes possible
- [BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) (BSD-3-Clause), whose virtual keyboard `IntelHIDButtons` follows; Linux's `intel-hid` driver and [YogaSMC](https://github.com/zhen-zen/YogaSMC) documented the Intel HID interface
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) for the OpenCore Install Guide

The configuration, SSDT and scripts are MIT licensed (see [LICENSE](LICENSE)). Each bundled kext, driver and OpenCore binary keeps its own upstream license.

## Disclaimer

Apple's license only permits macOS on Apple hardware. This project is not affiliated with Apple or Microsoft. Use it at your own risk and keep a backup.
