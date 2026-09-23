#!/bin/bash
#
# diy-part2.sh - built-in OpenWrt/x-wrt customization script (runs inside the
#                source tree, after .config has been loaded).
#
# Adds the TP-Link TL-R2005KSH (TELESQUARE LTE router, MT7620A + 32 MiB SPI
# flash) as a ramips/mt7620 device.
#
# How to use with the "miwifi-r3-router" style build repo:
#   1. put this file and mt7620a_tplink_tl-r2005ksh.dts in the repo root
#   2. either replace the repo's diy-part2.sh with this file, or append its
#      contents / call it from the existing diy-part2.sh
#   3. keep  DIY_P2_SH: diy-part2.sh  in the workflow env
#   4. in ap.config, no change is strictly required - this script flips the
#      device selection to the TL-R2005KSH
#
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
RAMIPS=target/linux/ramips
DEVICE=tplink_tl-r2005ksh
DTS=mt7620a_tplink_tl-r2005ksh.dts

echo "==> Installing device tree: $DTS"
cp "$SRC/$DTS" "$RAMIPS/dts/$DTS"

echo "==> Adding image recipe for $DEVICE"
if ! grep -q "Device/$DEVICE" "$RAMIPS/image/mt7620.mk"; then
	cat >> "$RAMIPS/image/mt7620.mk" <<'EOF'

# TP-Link TL-R2005KSH (TELESQUARE LTE router) - MT7620A, 64 MiB RAM,
# 32 MiB W25Q256 SPI-NOR, 4x LAN + 1x WAN, internal Qualcomm Gobi LTE modem.
# Flashed at 0x80000 behind Breed; the vendor's second image at 0x1000000 is
# left untouched as a way back to stock.
define Device/tplink_tl-r2005ksh
  SOC := mt7620a
  IMAGE_SIZE := 15872k
  IMAGES += factory.bin
  IMAGE/factory.bin := append-kernel | append-rootfs | pad-rootfs | check-size
  DEVICE_VENDOR := TP-Link
  DEVICE_MODEL := TL-R2005KSH
  SUPPORTED_DEVICES += tl-r2005ksh
  DEVICE_PACKAGES := kmod-usb2 kmod-usb-ohci \
	kmod-usb-serial-option kmod-usb-net-qmi-wwan uqmi
endef
TARGET_DEVICES += tplink_tl-r2005ksh
EOF
fi

echo "==> Patching 02_network (switch layout + MAC addresses)"
python3 - <<'PY'
p = 'target/linux/ramips/mt7620/base-files/etc/board.d/02_network'
s = open(p).read()
if 'tplink,tl-r2005ksh' in s:
    print('   already patched')
    raise SystemExit(0)

# switch layout taken from the vendor firmware (config.sh has CONFIG_WAN_AT_P4=y,
# internet.sh calls "config-vlan.sh 3 LLLLW" -> WAN at ESW port 4) and from
# admin_lan.sh, which maps the UI labels to ports as
#   lan_1 -> port 3, lan_2 -> port 2, lan_3 -> port 1, lan_4 -> port 0, wan -> 4
iface = '''\ttplink,tl-r2005ksh)
\t\tucidef_add_switch "switch0" \\
\t\t\t"3:lan:1" "2:lan:2" "1:lan:3" "0:lan:4" "4:wan" "6@eth0"
\t\t;;
'''
# base MAC lives at factory+0x4; the stock firmware used the same MAC for
# LAN and WAN.  Use macaddr_add "$(...)" 1 for WAN if your ISP does not bind.
macs = '''\ttplink,tl-r2005ksh)
\t\twan_mac=$(mtd_get_mac_binary factory 0x4)
\t\tlabel_mac=$(mtd_get_mac_binary factory 0x4)
\t\t;;
'''
out, in_if, in_mac, done_if, done_mac = [], False, False, False, False
for line in s.splitlines(True):
    out.append(line)
    if line.startswith('ramips_setup_interfaces()'):
        in_if = True
    elif line.startswith('ramips_setup_macs()'):
        in_mac = True
    if in_if and not done_if and 'case "$board" in' in line:
        out.append(iface); done_if, in_if = True, False
    elif in_mac and not done_mac and 'case "$board" in' in line:
        out.append(macs); done_mac, in_mac = True, False

if not (done_if and done_mac):
    raise SystemExit('ERROR: could not patch 02_network (anchors not found)')
open(p, 'w').write(''.join(out))
print('   patched')
PY

echo "==> Selecting the device in .config"
if [ -f .config ]; then
	sed -i 's/^CONFIG_TARGET_ramips_mt7620_DEVICE_xiaomi_miwifi-r3=y/# CONFIG_TARGET_ramips_mt7620_DEVICE_xiaomi_miwifi-r3 is not set/' .config
	sed -i 's/^# CONFIG_TARGET_ramips_mt7620_DEVICE_tplink_tl-r2005ksh is not set/CONFIG_TARGET_ramips_mt7620_DEVICE_tplink_tl-r2005ksh=y/' .config
	grep -q '^CONFIG_TARGET_ramips_mt7620_DEVICE_tplink_tl-r2005ksh=y' .config || \
		echo 'CONFIG_TARGET_ramips_mt7620_DEVICE_tplink_tl-r2005ksh=y' >> .config
	sed -i 's/^CONFIG_TARGET_PROFILE=.*/CONFIG_TARGET_PROFILE="DEVICE_tplink_tl-r2005ksh"/' .config
	# no 5 GHz / mini-PCIe card on this board
	sed -i 's/^CONFIG_PACKAGE_kmod-mt76x2=y/# CONFIG_PACKAGE_kmod-mt76x2 is not set/' .config
	sed -i 's/^CONFIG_PACKAGE_kmod-mt76x2-common=y/# CONFIG_PACKAGE_kmod-mt76x2-common is not set/' .config
	sed -i 's/^CONFIG_PACKAGE_kmod-mt76x02-common=y/# CONFIG_PACKAGE_kmod-mt76x02-common is not set/' .config
else
	echo "   no .config found - select the device manually:"
	echo "   CONFIG_TARGET_ramips_mt7620_DEVICE_tplink_tl-r2005ksh=y"
fi

echo "==> Done: device tplink_tl-r2005ksh registered"
