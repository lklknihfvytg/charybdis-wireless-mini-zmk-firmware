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

The board target is `nice_nano@2.0.0/nrf52840/zmk`. The base `nice_nano` target lacks ZMK's NVS/flash defaults and the P0.13 external-power node required by the trackball. Do not replace the target with the base board name.

To check all three dongle configurations without compiling firmware:

```bash
docker compose -f local-build/docker-compose.yml run --rm -e CONFIGURE_ONLY=1 builder bash ./local-build/build_single.sh qwerty dongle
```

Every normal build runs the same configuration check before compilation. It rejects missing flash storage, incorrect split roles, disabled BLE, and a right half without the sensor power rail. Configuration-only runs leave existing UF2 files untouched; they are not new firmware builds.

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
