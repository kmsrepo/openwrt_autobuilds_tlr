# openwrt_autobuilds_tlr

GitHub Actions autobuild of **OpenWrt (x-wrt)** for the **TP-Link TL-R2005KSH**
(TELESQUARE-branded LTE router, board `TLR-2005KSH`).

Push to `main` (or run the workflow manually) and the firmware lands in
[Releases](../../releases) and as a workflow artifact.

## Device

| item | value |
|---|---|
| SoC / RAM | MediaTek MT7620A, 64 MiB DDR2 |
| Flash | Winbond W25Q256, 32 MiB SPI-NOR |
| Network | internal 5-port 10/100 switch, 4x LAN + 1x WAN (WAN = ESW port 4, jacks wired in reverse) |
| USB | USB 2.0 host -> internal Qualcomm Gobi LTE module + external port |
| WiFi | MT7620A internal 2.4 GHz (`kmod-rt2800-soc`) |
| Console | uartlite @ 57600 8N1 |
| Model in build | `tplink_tl-r2005ksh` (profile `DEVICE_tplink_tl-r2005ksh`) |

Recovered from the stock firmware: see the comments in
`mt7620a_tplink_tl-r2005ksh.dts` (LED / reset-button / modem-reset GPIOs,
switch layout `mediatek,portmap = "llllw"`, flash map).

## Repo layout

| file | purpose |
|---|---|
| `ap.config` | OpenWrt/x-wrt configuration (ramips/mt7620, device selected) |
| `diy-part2.sh` | installs the DTS, the `Device/tplink_tl-r2005ksh` image recipe and the `02_network` switch/MAC entries into the source tree |
| `mt7620a_tplink_tl-r2005ksh.dts` | device tree (LEDs, reset button, modem reset/power/USB-mode GPIOs, flash partitions) |
| `.github/workflows/build.yml` | clone x-wrt -> install feeds -> apply config -> build -> release |

## Output

`bin/targets/ramips/mt7620/`:

* `…-tplink_tl-r2005ksh-squashfs-factory.bin` — kernel + squashfs rootfs,
  to be written at flash offset **0x80000**
* `…-tplink_tl-r2005ksh-squashfs-sysupgrade.bin` — for later upgrades from OpenWrt

## Flashing (from the Breed recovery shell at 192.168.1.1)

```
wget http://<your-pc>:8000/…-factory.bin     # Breed fetches into RAM, prints address
flash erase 0x80000 <size rounded up to 4 KiB>
flash write verify 0x80000 <ramaddr> <size>
boot flash 0x80000
```

Notes:

* Breed's autoboot does not know this board profile ("Reference design",
  no boot parameters), so every power-up needs `boot flash 0x80000` unless you
  set that as the autoboot command in Breed's 固件启动设置 page.
* The vendor's second firmware image at `0x1000000` (`firmware2`) is **not**
  touched by this layout, so a stock restore stays possible.
* The stock 2.4 GHz calibration is not in flash (the vendor used the SoC
  efuse). If WiFi fails to start, populate a 512-byte eeprom at `0x60000`
  (MAC at +0x4) and enable the commented `nvmem-cells` in `&wmac`.

## Credits

Workflow derived from [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
(MIT). Source tree: [x-wrt](https://github.com/x-wrt/x-wrt).
