# Bootloader build tools — SpacemiT K1 (Banana Pi F3)

Scripts that build the bootloader chain for the SpacemiT K1 SoC on
the Banana Pi F3 and stage the outputs into the AOSP tree under
`vendor/spacemit/k1/bootloader/`.

The chain is **OpenSBI → U-Boot** (no ATF, no OP-TEE) and the
sources are sibling repos `pi-opensbi/` and `pi-u-boot/`.

## Dependencies

```sh
sudo apt install bc bison build-essential curl flex git libssl-dev \
                 python3 python3-pip meson wget -y
pip3 install pycryptodome pyelftools shyaml --user
```

The RISC-V cross-toolchain (Bootlin glibc 2023.11-1) is downloaded
automatically on first build under `../toolchains/` — no manual
install required.

## Top-level: release_android.sh

Builds the full chain and stages the outputs into an AOSP tree in
one command:

```sh
./release_android.sh --aosp=<path-to-aosp>
```

Options:

| Option | Description |
|---|---|
| `--aosp=PATH`    | AOSP root path (required) |
| `--commit`       | commit the new binaries into the AOSP-side vendor repo |
| `--config=FILE`  | release a specific board config file (default: `config/boards/spacemit-k1.yaml`) |
| `--mode=MODE`    | `release`, `debug` or `factory` — build only one mode |
| `--no-build`     | skip rebuild, just re-stage existing artefacts |
| `--silent`       | silence build command output |

## Building one component

```sh
./build_opensbi.sh --config=config/boards/spacemit-k1.yaml
./build_uboot.sh   --config=config/boards/spacemit-k1.yaml
```

Common options on each: `--clean`, `--mode=[release|debug]`,
`--help`.

## Building everything for one board

```sh
./build_all.sh --config=config/boards/spacemit-k1.yaml
```

## Helpers

| Script | Purpose |
|---|---|
| `setup_android.sh --aosp=PATH --branch=BR` | initial AOSP-side branch prep for binary commits |
| `prepare_android_img.sh --config=... [--mode=...]` | assemble outputs under `out/` into the flash layout |
| `commit-binaries.sh --from-repo=... --to-repo=... --to-project=...` | commit refreshed binaries with a generated message |
| `secure.sh` | (placeholder) signing hook for factory builds |
