# S905L3A SDIO Wi-Fi Fix for OpenWrt

This directory contains a build-time, board-profiled DTB repair for S905L3A OpenWrt images.

The repair is deliberately limited to `SOC=s905l3a`. It never guesses reset GPIO, regulator or clock values. Hardware-tested profiles cover `M401A + RTL8822CS` and `SKYWORTH E900V22D/S905L3A + RTL8822CS`.

## Build behavior

The repository's `remake` script invokes `bin/patch-image` immediately after extracting the selected kernel DTBs. For `s905l3a-m401a`, the patcher:

1. Confirms that the expected SDIO, pinctrl, GPIO and regulator nodes exist.
2. Reads the actual phandles from that kernel's DTB.
3. Enables `mmc@ffe03000` as a non-removable 4-bit SDIO device.
4. Adds an `mmc-pwrseq-simple` node using GPIOX_7 as an active-low reset.
5. Compiles the result back to DTS and verifies the required properties.
6. Replaces the DTB in the image before packaging completes.

Other S905L3A boards currently log `No build-time S905L3A Wi-Fi profile` and remain unchanged. Non-S905L3A images do not execute this logic.

For `s905l3a-e900v22d`, the image builder creates a dedicated `meson-g12a-s905l3a-e900v22d.dtb` from the E900V22C base, updates its model/compatible values, removes the broken `wifi32k` dependency from the SDIO power sequence, disables the unused clock node and limits the non-removable eMMC controller to 100 MHz. It also adds model ID `308` to the installer's E900V22C/D eMMC layout so installation preserves the first 570 MiB and uses a 256 MiB boot partition. This profile is specific to the tested S905L3A/RTL8822CS unit and must not be used for similarly named S905L3B or S905L3 devices.

The board-specific first-boot defaults enable the RTL8822CS access point on the non-DFS 5 GHz channel 149 with country code `CN` and `VHT80`. This avoids the `country 00` `NO-IR` restriction that prevents hostapd from starting on 5 GHz while leaving the generated SSID and encryption settings unchanged.

## Build command

```bash
sudo ./remake -b s905l3a-m401a
sudo ./remake -b s905l3a-e900v22d
```

GitHub Actions can select `s905l3a-m401a` through the existing `openwrt_board` input.

`s905l3a-e900v22d` has `BUILD=yes`, so it is also included when `openwrt_board` or `remake -b` is set to `all`.

Do not copy the M401A profile based only on the SoC name. Verify each PCB's Wi-Fi chip, SDIO controller, reset GPIO, regulators and optional 32K clock first.
