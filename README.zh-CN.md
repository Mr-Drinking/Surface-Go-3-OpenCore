# Surface-Go-3-OpenCore

适用于 **Microsoft Surface Go 3（Pentium Gold 6500Y）** 的 OpenCore EFI，可以运行 **macOS Sequoia**。另外修好了电池显示，这是其他 Surface Go 3 EFI 都没有解决的问题。

[English](README.md)

| | |
| --- | --- |
| 测试机型 | Surface Go 3，Pentium Gold 6500Y，8GB 内存，128GB NVMe 固态硬盘 |
| macOS | Sequoia 15.8.1（24H32） |
| OpenCore | MOD 1.0.7（[OpenCore_NO_ACPI 构建](https://github.com/wjz304/OpenCore_NO_ACPI_Build)） |
| 机型（SMBIOS） | MacBookAir8,1（配合 `-no_compat_check` 和 `revpatch=sbvmm`） |
| 基于 | [jlempen/Surface-Go-2-OpenCore](https://github.com/jlempen/Surface-Go-2-OpenCore)（提交 `4fbf739`） |

Surface Go 3 其实就是换了 CPU 的 Surface Go 2，机身、屏幕、Intel AX200 网卡、读卡器和键盘盖都一样。Pentium Gold 6500Y 的频率和 Go 2 的 Core m3-8100Y 相同，核显也都是 UHD 615（`0x591C`）。而且和 Go 2 的 Pentium 4425Y 不同，它支持 AVX2，这是 macOS Ventura 及以后版本的硬性要求。Core i3-10100Y 版本没有测试过。64GB eMMC 版本不受支持，因为 macOS 没有 eMMC 驱动。

## 现状

**已在测试机上确认可用**

- 安装 macOS Sequoia，并从内置固态硬盘启动
- 电池电量，以及系统设置里的「电池」页（靠下面的修复）
- Wi-Fi（`itlwm` 驱动 + [HeliPort](https://github.com/OpenIntelWireless/HeliPort/releases) 客户端）
- 蓝牙
- 触摸屏
- 声音（ALC298，layout-id 69）
- 电源键

**预计可用（上游 EFI 在 Go 2 上可用，Go 3 上尚未确认）**

- 核显加速、亮度调节
- Surface 触控笔
- Type Cover 键盘和多指触控板
- 麦克风、耳机孔
- USB-C（包括视频输出）、microSD 读卡器
- 休眠（`hibernatemode 25`）

**实验性**

- 音量键：用仓库自带的 `IntelHIDButtons.kext`。在 Go 3 上确认可用之前，默认是关闭的。见[音量键](#音量键实验性)。

**不可用**
- 前置、后置、红外摄像头（Intel IPU3，macOS 没有驱动），NFC，自动旋转
- 睡眠：改用休眠，唤醒大约 10 秒
- 隔空投送、接力、随航等需要苹果兼容博通网卡的功能

## 和 Surface Go 2 EFI 的区别

1. **修好了电池。** Go 3 固件把电池 `\_SB.BAT1` 的 `_HID` 写成了 `"MSHW0146"`，而不是 Go 2 用的标准 `PNP0C0A`，所以 VirtualSMC 的 SMCBatteryManager 找不到它。修法是用一个 DSDT 补丁把这个 `_HID` 改名为 `XHID`（查找 `5F4849440D4D5348573031343600`，替换为 `584849440D4D5348573031343600`），再由 `SSDT-BAT1-SGO3.aml` 给设备补上标准的 `PNP0C0A`。如果以后固件更新导致改名补丁匹配不上，SSDT 会改为补一个兼容编号。读电量的方法和 Go 2 一样，都是读 EC，ECEnabler 和 SMCBatteryManager 会处理。源码见 [`ACPI-src/SSDT-BAT1-SGO3.dsl`](ACPI-src/SSDT-BAT1-SGO3.dsl)。
2. **电池页。** 上游把 PM Profile 改成 Mobile 的 FACP 补丁，匹配的是 Go 2 的 ACPI 启用值（`A0 A1`），而 Go 3 是 `F0 F1`。这里加了一条 Go 3 版（查找 `00080900B2000000F0F1`，替换为 `00020900B2000000F0F1`）。
3. **Wi-Fi 用 `itlwm` + HeliPort**：装好就能用，不需要给系统打补丁，所以 **SIP 保持全开**（`csr-active-config = 00000000`）。AirportItlwm 方案和相关驱动没有收录（见[可选：系统原生 Wi-Fi 菜单](#可选系统原生-wi-fi-菜单)）。
4. **删掉了上游的 `setup_var` 工具。** 它们按 Go 2 固件的位置修改 CFG Lock、VT-d、DVMT 变量，在 Go 3 上运行可能导致无法开机。CFG Lock 改由 `AppleXcpmCfgLock` 补丁处理，DVMT 改由显卡帧缓冲补丁处理。
5. 删掉了只在 Ventura、Sonoma 上才加载的驱动。
6. 序列号等 SMBIOS 字段是空的，启动前请**自己生成**（见下文）。

## 安装

需要：一台 Mac（用来运行脚本制作安装盘）；一个至少 16GB 的 U 盘（会被清空）；Type Cover 或 USB 键盘（OpenCore 菜单不能用触屏操作）。

### 1. 生成 SMBIOS

用 [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS)，或者 [OpenCorePkg 发布包](https://github.com/acidanthera/OpenCorePkg/releases)里的 `macserial`，生成 MacBookAir8,1 的序列号和 MLB：

```bash
./macserial -m MacBookAir8,1 -g -n 1
```

然后填进配置（也可以用 [ProperTree](https://github.com/corpnewt/ProperTree) 编辑 `PlatformInfo → Generic`）：

```bash
plutil -replace PlatformInfo.Generic.SystemSerialNumber -string "你的序列号" EFI/OC/config.plist
plutil -replace PlatformInfo.Generic.MLB -string "你的MLB" EFI/OC/config.plist
plutil -replace PlatformInfo.Generic.SystemUUID -string "$(uuidgen)" EFI/OC/config.plist
plutil -replace PlatformInfo.Generic.ROM -data "$(openssl rand -base64 6)" EFI/OC/config.plist
```

不要把含有你序列号的 `config.plist` 公开发到网上。

### 2. 下载 macOS Sequoia 安装包

能运行 Sequoia 的 Mac 上：`softwareupdate --fetch-full-installer --full-installer-version 15.8.1`。
较新的 Mac 上可能找不到 Sequoia。这时可以用 [Mist](https://github.com/ninxsoft/Mist) 或 [gibMacOS](https://github.com/corpnewt/gibMacOS) 从苹果的更新目录下载 Sequoia 的 `InstallAssistant.pkg`，放在 `make-usb.sh` 旁边。

建议把 [HeliPort.dmg](https://github.com/OpenIntelWireless/HeliPort/releases) 也放在旁边，这样它会被拷进安装盘，Surface 还没有 Wi-Fi 时也能装。

### 3. 制作安装盘

```bash
diskutil list external
sudo ./make-usb.sh disk4
```

把 `disk4` 换成你的盘。脚本会抹掉这个盘，写入完整的离线安装程序，把 OpenCore 拷进它的 EFI 分区，并在安装盘的 `PostInstall` 文件夹里放一份 EFI 和 `install-efi-internal.sh`。大于 64GB 的盘会分成 32GB 安装盘，加上一个 exFAT 数据分区 `DATA`。

安装盘上的那份 EFI 是专门为安装准备的：OpenCore 菜单不倒计时，会一直等你选；启动时显示白字日志；每次启动还会在安装盘的 EFI 分区里写一份 `opencore-*.txt` 日志。

### 4. 准备 Surface

在 Windows 里：备份资料；记下支架下方印着的序列号，以后想装回 Windows 时要用它下载 [Surface 恢复镜像](https://support.microsoft.com/surface-recovery-image)；可以顺便记下 [BitLocker 恢复密钥](https://aka.ms/myrecoverykey)。

进入 Surface UEFI（关机后按住**音量 +**，再按电源键）：

- Security → Secure Boot → Change configuration → 选 **None**。之后开机顶部出现红条是正常的。
- Boot configuration：把 **USB Storage** 拖到第一位。

### 5. 安装

1. 插好 Type Cover、安装盘和充电器，开机。想强制从 U 盘启动，按住**音量 −** 再按电源键。
2. 在 OpenCore 菜单里选 **Install macOS Sequoia**。
3. 打开磁盘工具，选择「显示」→「显示所有设备」，选中内置固态硬盘最上面一层（约 128GB），抹成 **APFS**，方案选 **GUID 分区图**。这一步会删除 Windows。
4. 把 macOS 装到这块盘上。中途每次重启都在菜单里选 **macOS Installer**，等它不再出现后选你的系统盘。全程不要拔安装盘。
5. 在设置助理里，先跳过联网和 Apple 账户，也不要开 FileVault。

### 6. 装好之后

1. 从 `PostInstall`（或者 HeliPort 的发布页）安装 HeliPort，连上 Wi-Fi，并勾选登录时启动。
2. 把 OpenCore 装到内置盘。脚本会自动找到内置盘的 EFI 分区，并把原有内容备份到 `~/EFI-backup-日期`：

   ```bash
   sudo "/Volumes/Install macOS Sequoia/PostInstall/install-efi-internal.sh"
   ```

3. 拔掉安装盘重启，确认 Surface 能自己启动。
4. 睡眠改用休眠：

   ```bash
   sudo pmset restoredefaults
   sudo pmset -a hibernatemode 25
   ```

5. 想要合适的 HiDPI 缩放，运行 [one-key-hidpi](https://github.com/jlempen/one-key-hidpi)，选 `(4) 1920x1280 Display`。
6. 如果休眠唤醒后蓝牙连不上，装一个 [Bluesnooze](https://github.com/odlp/bluesnooze)。

## 排查问题

- **一直进 Windows。** 开机没有红条，说明安全启动还开着。如果你是手动把 `EFI/` 拷进 U 盘、没有用 `make-usb.sh`，OpenCore 菜单会在 5 秒后自动启动默认项（Windows），要及时按方向键。也可以在 Windows 里从 U 盘启动：设置 → 系统 → 恢复 → 高级启动 → 使用设备。尽量别用扩展坞，有些硬盘盒在开机阶段认不出来。
- **看启动日志。** 把安装盘插回 Mac，运行 `sudo ./update-usb-efi.sh diskN`。它会把 `opencore-*.txt` 和内核崩溃记录拷到 `logs/`，并更新安装盘上的 EFI。如果一份日志都没有，说明 OpenCore 根本没运行。
- **重置 NVRAM**：在 OpenCore 菜单按空格显示隐藏项，选 Reset NVRAM。

## 音量键（实验性）

**为什么需要一个驱动。** Go 3 固件只把音量键发给 Intel HID 设备（`INT33D5`，`\_SB.HIDD`）：EC 事件 `_QD1`–`_QD4` 会向它发送通知码 `0xC4`–`0xC7`（音量加、减的按下和松开），而 macOS 没有这个设备的驱动。Go 2 只有在 Windows 的 Intel HID 驱动启用之后才走这条路，否则会退回到模拟的 PS/2 键盘（`PS2K`），由 VoodooPS2 接收；Go 3 则完全没有 `PS2K`。YogaSMC 的 YogaHIDD 能识别这些事件，但只能借 VoodooPS2 发出按键。

**`IntelHIDButtons.kext` 做了什么。** 它挂在 `INT33D5` 上，告诉固件按键驱动已加载（依次调用 `BTNL`、`HDSM`、`BTNE`），再用自己的虚拟键盘把 `0xC4`–`0xC7` 转成音量键。调用 `BTNL` 后，电源键也会从 ACPI 电源键设备改到这个设备上（`0xCE` / `0xCF`），所以驱动会照原来 ACPI 设备的方式，把电源键按下通知给 macOS。源码和编译脚本见 [`Kexts-src/IntelHIDButtons`](Kexts-src/IntelHIDButtons)，用命令行工具和 [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) 就能编译，不需要 Xcode。

**加到已经装好的系统里。** 在 Surface 上连好 Wi-Fi，在终端运行下面几行（脚本会先备份 `config.plist`，序列号等不会动）：

```bash
cd ~/Downloads
curl -L -o Surface-Go-3-OpenCore.zip https://github.com/Mr-Drinking/Surface-Go-3-OpenCore/archive/refs/heads/main.zip
unzip -q -o Surface-Go-3-OpenCore.zip
sudo bash Surface-Go-3-OpenCore-main/add-kext-internal.sh IntelHIDButtons
```

拔掉 U 盘安装盘后重启。运行 `ioreg -rc IntelHIDButtons | grep -E 'DSMFunctions|ButtonCaps'` 能看到驱动有没有在运行。

**撤销。** 如果 Surface 开不了机，就按住音量 − 从 U 盘安装盘启动，再把脚本提示的备份拷回去：

```bash
sudo diskutil mount disk0s1
sudo cp ~/config-backup-日期-时间.plist /Volumes/EFI/EFI/OC/config.plist
```

## 可选：系统原生 Wi-Fi 菜单

AirportItlwm 可以用系统自带的 Wi-Fi 菜单。但在 Sequoia 上，它需要从旧版 macOS 提取的苹果驱动 `IOSkywalkFamily.kext` 和 `IO80211FamilyLegacy.kext`，还要加载 `AMFIPass.kext`、部分关闭 SIP（`csr-active-config = 03080000`），并且每次 macOS 更新后都要用 [OCLP-Mod](https://github.com/laobamac/OCLP-Mod/releases) 重新给系统打补丁。这里不分发苹果的这些二进制文件；需要的驱动和步骤见 [jlempen/Surface-Go-2-OpenCore](https://github.com/jlempen/Surface-Go-2-OpenCore)。

## 性能预期

Pentium Gold 6500Y 的 Geekbench 6 成绩大约是单核 900–1050、多核 1750–1850，和 2018 款 MacBook Air 差不多，但没有风扇。浏览网页、写文档、看视频都没问题；不过在这台机器上，Windows 11 更流畅，而且有睡眠、摄像头和适合触屏的界面。续航预计 5 小时左右（来自 Go 2 的数据）。

## 致谢

- [jlempen](https://github.com/jlempen/Surface-Go-2-OpenCore) 和 [kingo132](https://github.com/kingo132/surface-go2-hackintosh)：本项目基于他们的 Surface Go 2 EFI
- [acidanthera](https://github.com/acidanthera)：OpenCore、Lilu、VirtualSMC、WhateverGreen、AppleALC、NVMeFix、RestrictEvents、HibernationFixup、CPUFriend、BrcmPatchRAM（BlueToolFixup）、VoodooPS2；[btwise](https://gitee.com/btwise/OpenCore_NO_ACPI) / [wjz304](https://github.com/wjz304/OpenCore_NO_ACPI_Build)：OpenCore_NO_ACPI 构建
- [OpenIntelWireless](https://github.com/OpenIntelWireless)：itlwm、IntelBluetoothFirmware、HeliPort
- [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C)、[ECEnabler](https://github.com/1Revenger1/ECEnabler)、[RealtekCardReader](https://github.com/0xFireWolf/RealtekCardReader) / [RealtekCardReaderFriend](https://github.com/0xFireWolf/RealtekCardReaderFriend)、[VoltageShift](https://github.com/sicreative/VoltageShift)
- [linux-surface](https://github.com/linux-surface/acpidumps)：公开的 Surface Go 3 ACPI 表让电池和音量键修复成为可能
- [BrightnessKeys](https://github.com/acidanthera/BrightnessKeys)（BSD-3-Clause）：`IntelHIDButtons` 的虚拟键盘照它的方式实现；Linux 的 `intel-hid` 驱动和 [YogaSMC](https://github.com/zhen-zen/YogaSMC) 提供了 Intel HID 接口的参考
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/)：OpenCore 安装指南

配置文件、SSDT 和脚本采用 MIT 许可证（见 [LICENSE](LICENSE)）。收录的各个驱动和 OpenCore 二进制文件沿用各自上游项目的许可证。

## 免责声明

苹果的许可协议只允许在苹果硬件上运行 macOS。本项目与苹果和微软无关。使用风险自负，请先做好备份。
