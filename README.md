# SpacemiT K3 bootloader build

The K3 config selects upstream-based U-Boot and OpenSBI from the
`u-boot/` and `opensbi/` sibling repositories. This branch contains only
the K3 board config.

## Build and stage

Requirements: a Linux host, `make`, `bison`, `flex`, `dtc`, Python 3,
`shyaml`, and the build's RISC-V cross-toolchain. The scripts download their
board's toolchain when needed.

```sh
bash release_android.sh --aosp=../../aosp --config=config/boards/spacemit-k3.yaml
```

This builds OpenSBI and U-Boot, assembles flash images and stages them in
`vendor/rise/spacemit/k3/bootloader/`. Run from this repository inside the sibling
bootloader checkout described by the RISE manifest documentation.

Use `--mode=release` or `--mode=debug` to select a build mode, and
`--no-build` to stage existing outputs. `--commit` explicitly commits
staged binaries; the default stages files without creating commits.
The default also leaves the Git index unchanged.

Individual components can be rebuilt with:

```sh
bash build_opensbi.sh --config=config/boards/spacemit-k3.yaml --mode=release
```

```sh
bash build_uboot.sh --config=config/boards/spacemit-k3.yaml --mode=release
```

Rebuild Android after refreshing the vendor prebuilts.

## K3 flash artifacts

The Pico-ITX boot chain lives in SPI-NOR; Android lives on UFS/SCSI device 0.
Use the Android product's `flash_pico_itx.sh` helper. It writes named raw NOR
partitions, and its DFU path creates the UFS GPT from U-Boot's compiled
`partitions` environment. The delivered `partition_nor.json` describes the
NOR offsets; it does not create an Android GPT.

The K1 Android JSON partition layout is excluded from this branch.
`gen_imgcfg.py` remains a legacy utility and does not describe the active K3
storage contract. SD/genimage and vendor JSON
`multi_flash` workflows are unsupported; `--sdcard` fails explicitly.

SPL loads the combined U-Boot FIT at NOR offset `0x210000`. This FIT includes
OpenSBI in both debug and release builds; the flasher does not write the
standalone OpenSBI image into the legacy NOR slot. Environment images are
64 KiB to fit the existing NOR environment partition.

The NOR bootinfo still carries the vendor fallback SPL1 offset `0xa0000`,
which is also the environment slot. The shipped flasher programs only the
primary SPL0 at `0x20000`. BROM fallback to a second SPL copy has not been
validated on hardware.
