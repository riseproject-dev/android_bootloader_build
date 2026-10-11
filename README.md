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
