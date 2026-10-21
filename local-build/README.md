# 🛠️ Local ZMK Firmware Builds (Dockerized)

This setup provides a **fast, containerized build environment** for [ZMK Firmware](https://zmk.dev), allowing you to compile firmware locally without pushing changes to GitHub or installing any toolchains on your system.

- **Rapid feedback loop for keymap and overlay changes**
- **No GitHub Actions delay**
- **No toolchain installation required**
- **Cross-platform, reproducible builds**
- **Automatic shield and keymap discovery**
- **PMW3610 driver integration**
- **Isolated build sandboxes for each shield**
- **ZMK Studio USB-UART support**
- **Artifacts are published by keymap to a persistent folder for easy access**

---

## Quick Start

### 1. Prerequisites

Make sure you have:

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- This repository cloned on your host machine

---

### 2. Start the Build Container

Build the QWERTY Bluetooth firmware with:

```bash
docker compose -f local-build/docker-compose.yml run --rm builder bash ./local-build/build_single.sh qwerty bt
```

To build all three QWERTY dongle firmware files, run:

```bash
docker compose -f local-build/docker-compose.yml run --rm builder bash ./local-build/build_single.sh qwerty dongle
```

The dongle build creates `charybdis_dongle.uf2`, `charybdis_left.uf2`, and `charybdis_right.uf2` in `firmwares/charybdis_dongle/qwerty/`. Change `qwerty` to another keymap name in `config/keymap/` as needed. Add `left` or `right` as a third argument to build only that half, for example: `docker compose -f local-build/docker-compose.yml run --rm builder bash ./local-build/build_single.sh qwerty dongle right`.

The first run downloads and initializes the ZMK/Zephyr workspace. Later builds reuse it and the per-target build directories. Running the container without extra arguments builds QWERTY Bluetooth firmware. To build another keymap or format, pass the script and its arguments as shown above.

ZMK and the PMW3610 driver are pinned in `config/west.yml` to the revisions
used by the hardware-tested baseline. ZMK's imported manifest pins its Zephyr
and other dependencies. Dependency upgrades must be deliberate changes to
these revisions, followed by `west update` and validation; normal rebuilds
keep the existing checkouts.

The board target is `nice_nano@2.0.0/nrf52840/zmk`. The base `nice_nano` target lacks ZMK's NVS/flash defaults and the P0.13 external-power node required by the trackball. Do not replace the target with the base board name.

The shields are loaded directly from this repository through the
`boards/zephyr/module.yml` external module. Builds never copy boards or keymaps
into ZMK's source tree. BT and dongle variants have unique shield names, so old
injected shields cannot take precedence. Their shared matrix lives in
`boards/shields/charybdis_common/charybdis.dtsi`; output UF2 names stay unchanged.
`build_setup.sh` is a compatibility wrapper around the cached `build_single.sh`
builder; it no longer copies the entire workspace into temporary directories.

To check all three dongle configurations without compiling firmware:

```bash
docker compose -f local-build/docker-compose.yml run --rm -e CONFIGURE_ONLY=1 builder bash ./local-build/build_single.sh qwerty dongle
```

Every normal build runs the same configuration check before compilation. It rejects missing flash storage, incorrect split roles, disabled BLE, and a right half without the sensor power rail. Configuration-only runs leave existing UF2 files untouched; they are not new firmware builds.

The current pointer profile uses 800 CPI with a 1/1 movement scale (2.5 times
the saved 2026-10-21 checkpoint's speed). The sensor uses its default 8 ms active
RUN period; `CONFIG_PMW3610_ALT_REPORT_INTERVAL_MIN=0` forwards each motion
sample without another software rate limiter. This targets about 125 samples/s
before BLE transport; the actual USB report cadence depends on the radio link.
The 1/16 slow-pointer and scroll scales, rest timings, 10-minute sleep timeout,
and Bluetooth transmit power are unchanged. Normal builds disable USB logging.
Battery-life and cursor-smoothness improvements require hardware measurement.

Sensor orientation is defined alongside its wiring in
`config/charybdis_pmw3610.dtsi` using `swap-xy`, `invert-x` and `invert-y`.
Do not add separate Kconfig orientation overrides.

The dongle profile also allows automatic BLE 2M PHY negotiation on the
dongle/right link. The existing left firmware keeps using 1M. The central
received-event queue is 32 entries instead of 5; dongle/right input queues are
32 entries instead of 16; right-side connection, ACL and L2CAP transmit buffers
are 6 instead of 3. These buffers provide room for separate X/Y notifications
and simultaneous key traffic. This does not prove that previous stutters were
queue overflows. Transmit power, connection interval/latency, sensor timing,
and sleep settings remain unchanged from the first pointer profile.

A 30-second Windows Raw Input test of the first pointer profile recorded about
70 nonzero motion events/s, with median gaps around 14 ms and some gaps over
100 ms, both with and without typing. The revised BLE/buffer configuration
still needs the same test after flashing; configured sensor timing is not a
measurement of host cursor smoothness.

### 3. Firmware Output

Firmware files are placed in the `firmwares/` directory in the repository, grouped by format (bt/dongle) and keymap:

```bash
firmwares/
├── charybdis_bt
│   ├── colemak_dh
│   │   ├── charybdis_left.uf2
│   │   └── charybdis_right.uf2
│   └── qwerty
│       ├── charybdis_left.uf2
│       └── charybdis_right.uf2
├── charybdis_dongle
│   ├── colemak_dh
│   │   ├── charybdis_dongle.uf2
│   │   ├── charybdis_left.uf2
│   │   └── charybdis_right.uf2
│   └── qwerty
│       ├── charybdis_dongle.uf2
│       ├── charybdis_left.uf2
│       └── charybdis_right.uf2
└── settings_reset.uf2
```

---

## 💡 Tips

### Drop into a shell for troubleshooting

This will give you an interactive bash prompt with all dependencies loaded, so you can run or debug the script manually:

```bash
docker compose -f local-build/docker-compose.yml run --rm --entrypoint bash builder
```
Once inside the shell, you can execute the script manually, or go troubleshooting:

```bash
bash ./local-build/build_single.sh qwerty dongle
```

---

## Troubleshooting

For a firmware built with USB logging, Windows can capture the serial output
without installing a terminal application:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-build\capture-usb-log.ps1 -Port COM3 -Seconds 60
```

Use the device's actual COM port; omit `-Port` when exactly one COM port exists.
Logs are saved under `build/logs`. During capture, press keys on both halves.

To measure mouse events delivered to Windows without changing the firmware:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\local-build\measure-pointer.ps1 -Seconds 30
```

For the first 15 seconds, move only the trackball continuously. For the last
15 seconds, keep moving it while typing. Leave other mice stationary. The script
uses a message-only Raw Input window, keeps the current application focused,
and saves mouse device IDs, arrival times and movement deltas to `build/logs`.
It also reads the Windows hide-pointer-while-typing setting without changing it.
These are host event arrival times, not a direct sensor or radio sampling-rate
measurement; physical pauses and Windows event batching can affect the results.

- Enable USB logging to troubleshoot the firmware while it's running.
  - This is disabled by default since it has a significant negative impact on battery life
  - To turn it on, enable the variable at the top of the [build script](local-build/build_setup.sh), then follow instructions [here](https://zmk.dev/docs/development/usb-logging) to see the log stream on your computer.
  - Since this is a split keyboard you'll likely have to use `sudo tio /dev/ttyACM1` or `sudo tio /dev/ttyACM2` depending on what side you want to see logs for.
    - If you don't know what tty devices your system can see, run this command to find out `ls -l /dev/serial/by-id`
    - To see the PMW3610 sensor logs you'll also need to enable the following Kconfig options in `config/charybdis_right.conf`
      - CONFIG_LOG=y
      - CONFIG_LOG_DEFAULT_LEVEL=3
      - CONFIG_LOG_MODE_DEFERRED=n
      - CONFIG_PMW3610_LOG_LEVEL_DBG=y
      - CONFIG_LOG_BACKEND_UART=y
      - CONFIG_USB_CDC_ACM=y
      - CONFIG_LOG_MODE_DEFERRED=n
- If the firmware is not generated as expected, use the interactive shell method above to inspect `/workspaces/zmk/firmwares` or rerun the script with debugging.
- Check the script output for any warnings or errors about missing shields, keymaps, or build failures. If you'd like to save the script output to a file for local parsing in a text editor start the build container with this command:
  ```bash
  docker compose -f local-build/docker-compose.yml run --rm builder > logs.txt 2>&1
  ```

---

## 📚 More Resources

- [ZMK Documentation](https://zmk.dev/docs)
- [ZMK Dev Container Setup](https://zmk.dev/docs/development/local-toolchain/setup/container)
