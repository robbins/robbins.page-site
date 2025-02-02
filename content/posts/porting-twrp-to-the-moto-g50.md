+++
title = "Porting TWRP to the Moto G50 (ibiza)"
date = "2025-01-19"

[taxonomies]
tags=["android"]
+++

{{ note(header="Disclaimer", body="I did the bringup for this device in August 2023, so I may have forgotten some things by now. I also tried to remove extraneous information in the tree that I thought was required at the time to solve
whatever issue I was facing, but ended up not being necessary, but I may be missing some parts. For the full tree, see [GitHub](https://github.com/robbins/android_device_motorola_ibiza-twrp)") }}

# What is TWRP
TWRP is a custom recovery for Android. When installed (on phones with an unlocked bootloader), it has more features than the stock Android recovery, such as the ability to flash custom ROMs and kernels,
flashing & backing up specific partitions, accessing files, a shell, and more.

# Gathering Device Information
First, we need to collect some information about the device. The device can be booted into fastboot mode (bootloader) by rebooting the phone while holding Volume Up.

`fastboot getvar all` displays all bootloader variables. Here's some of the useful ones.

```shell
> fastboot getvar all
(bootloader) product: ibiza
(bootloader) primary-display: djn_nt36525c_hd_vid
(bootloader) securestate: flashing_unlocked
(bootloader) verity-state: enforcing (0)
(bootloader) sku: XT2137-1
(bootloader) slot-count: 2
(bootloader) is-userspace: no
```

- The bootloader is unlocked
- A/B partitioning is used
- Device codename is ibiza
- Model number is XT2137-1

By booting into recovery (reboot the phone while holding Volume Down), and then selectring fastboot, we can run the same command from userspace fastboot:
{{ note(clickable=true, hidden=true, header="Bootloader variables", body="
```shell
> fastboot getvar all
(bootloader) cpu-abi:arm64-v8a
(bootloader) super-partition-name:super
(bootloader) is-logical:xbl_b:no
(bootloader) is-logical:xbl_config_b:no
(bootloader) is-logical:ssd:no
(bootloader) is-logical:sde:no
(bootloader) is-logical:sdb:no
(bootloader) is-logical:xbl_config_a:no
(bootloader) is-logical:keymaster_a:no
(bootloader) is-logical:abl_a:no
(bootloader) is-logical:vbmeta_a:no
(bootloader) is-logical:bluetooth_a:no
(bootloader) is-logical:uefisecapp_a:no
(bootloader) is-logical:sdc:no
(bootloader) is-logical:misc:no
(bootloader) is-logical:devcfg_a:no
(bootloader) is-logical:hyp_a:no
(bootloader) is-logical:logo_a:no
(bootloader) is-logical:fsg_a:no
(bootloader) is-logical:boot_a:no
(bootloader) is-logical:dtbo_a:no
(bootloader) is-logical:tz_a:no
(bootloader) is-logical:sdd:no
(bootloader) is-logical:vendor_boot_b:no
(bootloader) is-logical:dsp_a:no
(bootloader) is-logical:prov_a:no
(bootloader) is-logical:uefisecapp_b:no
(bootloader) is-logical:tz_b:no
(bootloader) is-logical:storsec_b:no
(bootloader) is-logical:sda:no
(bootloader) is-logical:userdata:no
(bootloader) is-logical:abl_b:no
(bootloader) is-logical:dtbo_b:no
(bootloader) is-logical:rpm_a:no
(bootloader) is-logical:boot_b:no
(bootloader) is-logical:dsp_b:no
(bootloader) is-logical:modem_b:no
(bootloader) is-logical:modem_a:no
(bootloader) is-logical:rpm_b:no
(bootloader) is-logical:keymaster_b:no
(bootloader) is-logical:devcfg_b:no
(bootloader) is-logical:prov_b:no
(bootloader) is-logical:hyp_b:no
(bootloader) is-logical:qupfw_b:no
(bootloader) is-logical:logo_b:no
(bootloader) is-logical:fsg_b:no
(bootloader) is-logical:bluetooth_b:no
(bootloader) is-logical:xbl_a:no
(bootloader) is-logical:storsec_a:no
(bootloader) is-logical:sdf:no
(bootloader) is-logical:vendor_boot_a:no
(bootloader) is-logical:qupfw_a:no
(bootloader) is-logical:vbmeta_system_b:no
(bootloader) is-logical:vbmeta_b:no
(bootloader) is-logical:super:no
(bootloader) is-logical:metadata:no
(bootloader) is-logical:vbmeta_system_a:no
(bootloader) is-logical:product_a:yes
(bootloader) is-logical:product_b:yes
(bootloader) is-logical:system_a:yes
(bootloader) is-logical:system_b:yes
(bootloader) is-logical:system_ext_a:yes
(bootloader) is-logical:system_ext_b:yes
(bootloader) is-logical:vendor_a:yes
(bootloader) is-logical:vendor_b:yes
(bootloader) treble-enabled:true
(bootloader) is-userspace:yes
(bootloader) version-vndk:30
(bootloader) version-os:11
(bootloader) first-api-level:30
(bootloader) dynamic-partition:true
```") }}

- We have dynamic partitions
- The SOC is ARM64-v8
- We have Project Treble
- The logical and physical partitions are all listed
- The device shipped on API 30
- The target VNDK version is API 30

# Obtaining partition images
On a rooted device connected via ADB, run:
```shell
ls -l /dev/block/platform/soc/4804000.ufshc/by-name/
```

to list all partitions, and 

```shell
adb shell "su -c 'dd bs=1m if=/dev/block/bootdevice/by-name/partition_name 2> /dev/null'" > partition_name.img
```

to get an image of a given partition.

# Unpacking the boot and vendor_boot partitions
After dumping either `boot_a` or `boot_b`, run the `unpack_bootimg.py` [script](https://cs.android.com/android/platform/superproject/main/+/main:system/tools/mkbootimg/unpack_bootimg.py) as follows:

```shell
unpack_bootimg.py --boot_img boot_a.img --out boot_a_output
boot_magic: ANDROID!
kernel_size: 41871872
ramdisk size: 9519015
os version: 11.0.0
os patch level: 2023-05
boot image header version: 3
command line args:
```

The reason we have only a subset of the information available here is because of the split of the boot partition into boot and [vendor boot](https://source.android.com/docs/core/architecture/partitions/vendor-boot-partitions) partitions,
which separates generic and vendor specific information.

As output, we have `kernel`, which is the executable kernel image itself, `mkbootimg_args.json`, which is a JSON version of some of the above information, and `ramdisk`, a gzip-compressed CPIO archive. 
We can extract the boot ramdisk filesystem contents with `gunzip -c ramdisk | cpio -idm`.

```
acct        d              dev                    linkerconfig   odm_file_contexts      plat_property_contexts  product_property_contexts  sepolicy    system_ext_file_contexts      vendor_property_contexts
apex        data           etc                    metadata       odm_property_contexts  postinstall             prop.default               storage     system_ext_property_contexts
bin         data_mirror    first_stage_ramdisk    mnt            oem                    proc                    ramdisk.cpio               sys         tmp
bugreports  debug_ramdisk  init                   module_hashes  overlay.d              product                 res                        system      vendor
config      default.prop   init.recovery.qcom.rc  odm            plat_file_contexts     product_file_contexts   sdcard                     system_ext  vendor_file_contexts
```

Performing the same steps with `vendor_boot_a.img` reveals:
```shell
boot magic: VNDRBOOT
vendor boot image header version: 3
page size: 0x00001000
kernel load address: 0x00008000
ramdisk load address: 0x01000000
vendor ramdisk size: 704488
vendor command line args: console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0x04C8C000 androidboot.hardware=qcom androidboot.console=ttyMSM0 androidboot.memcg=1 lpm_levels.sleep_disabled=1 video=vfb:640x400,bpp=32,memsize=3072000 msm_rtb.filter=0x237 service_locator.enable=1 androidboot.usbcontroller=4e00000.dwc3 swiotlb=0 loop.max_part=7 cgroup.memory=nokmem,nosocket iptable_raw.raw_before_defrag=1 ip6table_raw.raw_before_defrag=1 firmware_class.path=/vendor/firmware_mnt/image androidboot.hab.csv=18 androidboot.hab.product=ibiza androidboot.hab.cid=50 buildvariant=user
kernel tags load address: 0x00000100
product name: 
vendor boot image header size: 2112
dtb size: 323520
dtb address: 0x0000000001f00000
```

and we can access the filesystem in the same way.

```
first_stage_ramdisk  lib
```

# Getting the sources
From `https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp`:
Run:
```
> repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1
> repo sync
```

# Building (and failing, and building again)
Next, we can follow the [AOSP documentation](https://source.android.com/docs/setup/create/new-device#build-a-product) for creating a new device in order to setup the initial makefiles for the device tree.
Then, we can setup our build with `lunch twrp-ibiza`, and then compile the build target for our device. Since our stock recovery is in the boot ramdisk, we want `mka bootimage`. The full list is [here](https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp/blob/twrp-12.1/README.md).
The remaining parts of the process involves cross-referencing our device information with build system errors and boot logs in order to decide what flags need to be set in the device tree.

Upon initial compile we receive this error:
```
build/make/core/board_config.mk:193: error: Target architectures not defined by board config: device/motorola/ibiza/BoardConfig.mk.
```

The Android build system shows that we need to set either `TARGET_ARCH` or `TARGET_ARCH_SUITE`.
To `BoardConfig.mk` we add:
```Make
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := kryo
TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := kryo
```

Next, we can implement A/B partitioning. Using [this documentation](https://source.android.com/docs/core/ota/ab/ab_implement) and the information we gathered above, we set:
```Makefile
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS := \
  boot \
  system \
  vendor \
  vendor_boot \
  system_ext \ 
  product \
  dtbo \
  vbmeta \
  vbmeta_system

PRODUCT_PACKAGES += \
  update_engine \
  update_verifier
```
in `device.mk`. We can check this against the partitions provided in a stock OTA and ensure they match.

We also add the following to `BoardConfig.mk` as directed:
```Makefile
TARGET_NO_RECOVERY := true
BOARD_USES_RECOVERY_AS_BOOT := true
```
and we can verify this by confirming that we indeed don't have a recovery partition - the recovery is in the boot image instead.

Next, we need to define our kernel to fix this error. We'll use the prebuilt one we extracted earlier and copy it to `prebuilt/kernel`.
```
vendor/twrp/build/tasks/kernel.mk:108: error: BOARD_KERNEL_IMAGE_NAME not defined..
```

In `BoardConfig.mk`:
```Makefile
TARGET_PREBUILT_KERNEL := device/motorola/ibiza/prebuilt/kernel
LOCAL_KERNEL := $(TARGET_PREBUILT_KERNEL)
PRODUCT_COPY_FILES := \
  $(LOCAL_KERNEL):kernel
```

This copies the prebuilt kernel to `$OUT/kernel`.

We then solve
```
Could not find ui.xml for TW_THEME: not set
Set TARGET_SCREEN_WIDTH and TARGET_SCREEN_HEIGHT to automatically select
an appropriate theme, or set TW_THEME to one of the following:
landscape_hdpi landscape_mdpi portrait_hdpi portrait_mdpi watch_mdpi
```

by setting the following in `device.mk`:
```
TARGET_SCREEN_WIDTH := 720
TARGET_SCREEN_HEIGHT := 1600
```

Finally, we define our boot image size in bytes in `BoardConfig.mk` that we got from the bootloader: `(bootloader) boot_a: offset=619392KB, size=98304KB`.
```Makefile
BOARD_BOOTIMAGE_PARTITION_SIZE := 0x5dc0000
```

We now finally have a `boot.img` that compiles successfully. However, trying to boot it with `fastboot boot boot.img` fails, rebooting back to the bootloader almost immediately.

Now's the time to set the arguments we dumped from the stock `boot.img`. Using that information, we set the following in BoardConfig.mk:
```Makefile
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_BASE          := 0x00000000
BOARD_KERNEL_OFFSET        := 0x00008000
BOARD_RAMDISK_OFFSET       := 0x01000000
BOARD_KERNEL_TAGS_OFFSET   := 0x00000100
BOARD_DTB_OFFSET           := 0x01f00000

BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img
BOARD_INCLUDE_RECOVERY_DTBO := true
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_BOOT_HEADER_VERSION := 3

BOARD_MKBOOTIMG_ARGS += --base $(BOARD_KERNEL_BASE)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --dtb $(BOARD_PREBUILT_DTBIMAGE_DIR)/dtb.img

```

as well as this information on [DTB](https://source.android.com/docs/core/architecture/bootloader/dtb-images) and [recovery images](https://source.android.com/docs/core/architecture/bootloader/recovery-images).
The partition images were dumped in the same way.

Next, following some other trees as examples, we set partition sizes and include the `fstab.qcom` from the vendor_boot ramdisk in `BoardConfig.mk`. This fstab contains the required FBE encryption options on the `userdata` partition
that will be required for decryption support later.

This `fstab` should only include dynamic partitions, and the `userdata`, `metadata`, and `misc` partitions, as these are required for decryption. All other partitions should be in `twrp.flags`.

```Makefile
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab

BOARD_BOOTIMAGE_PARTITION_SIZE := 98304000
BOARD_DTBOIMG_PARTITION_SIZE := 24576000
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 98304000
BOARD_SUPER_PARTITION_SIZE := 12582912000
TARGET_COPY_OUT_VENDOR := vendor
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USES_MKE2FS := true
```

Since we have dynamic partitions (and userspace fastboot), we need to include the Fastboot HAL and fastboot daemon:
```Makefile
PRODUCT_PACKAGES += \
    android.hardware.fastboot@1.0-impl-mock \
    fastbootd
```

Booting our compiled boot image now results in a black screen which flashes grey in a loop. The device isn't recognized via ADB, so it looks like TWRP is failing to initialize.
We need to set `TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888` - I'm not exactly sure what this does, but it fixed the issue here.

Finally, we now boot into TWRP! But there's still lots more work to be done.

# Fixing the touchscreen
Initially, the screen wouldn't respond to taps. According to `(bootloader) primary-display: djn_nt36525c_hd_vid`, we have a Novatek touchscreen. And in the stock boot image, we find Novatek
firmware and kernel modules:
```
recovery/root/vendor/lib/modules/1.1/nova_0flash_mmi.ko
recovery/root/vendor/lib/modules/nova_0flash_mmi.ko
recovery/root/vendor/firmware/novatek_ts_mp.bin
recovery/root/vendor/firmware/novatek_ts_fw.bin
```

so we add those files to our tree and set `TW_LOAD_VENDOR_MODULES := "nova_0flash_mmi.ko"` to load the module on boot.

# Fixing ADB access
We still can't access the device over USB, and it's not visible in `lsusb` or `dmesg`. First, we exclude the default USB configuration with `TW_EXCLUDE_DEFAULT_USB_INIT := true`.
Next, we add `init.recovery.usb.rc` to our tree. Finally, we add this snippet to ensure ADB still works when MTP is enabled (which is the case by default when booting into TWRP), so if you think it should be working, try disabling MTP first:
```
on property:sys.usb.config=mtp && property:sys.usb.configfs=1
    write /config/usb_gadget/g1/configs/b.1/strings/0x409/configuration "mtp"
    symlink /config/usb_gadget/g1/functions/mtp.gs0 /config/usb_gadget/g1/configs/b.1/f1
    write /config/usb_gadget/g1/UDC ${sys.usb.controller}
    setprop sys.usb.state ${sys.usb.config}

on property:sys.usb.config=mtp,adb && property:sys.usb.configfs=1
    start adbd

on property:sys.usb.ffs.ready=1 && property:sys.usb.config=mtp,adb && property:sys.usb.configfs=1
    write /config/usb_gadget/g1/configs/b.1/strings/0x409/configuration "mtp_adb"
    symlink /config/usb_gadget/g1/functions/mtp.gs0 /config/usb_gadget/g1/configs/b.1/f1
    symlink /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f2
    write /config/usb_gadget/g1/UDC ${sys.usb.controller}
    setprop sys.usb.state ${sys.usb.config}
```

The two important values for `sys.usb.config` are `adb` and `mtp,adb`, so ensure that they are included in your usb RC.

# Fixing decryption
This TWRP build isn't usable yet unless we are able to decrypt `userdata`. A lot of the process is described [here](https://github.com/TeamWin/android_device_qcom_twrp-common), which is a device tree that contains QCOM encryption
setup and which we need to inherit from, so I won't mention the steps it already includes. It's doing a lot of the heavy lifting here in terms of defining and starting the required services like `gatekeeper`.

A crucial step here is to now use libraries and `.rc` files from the `system` or `vendor` partitions, as the stock recovery doesn't have the need to decrypt `userdata` and thus the stock boot partition will not contain the require files.

For example, I ran into this error, which stumped me for a while:
```
01-29 00:11:29.971   492   494 E rpmb_ufs: Unable to open /dev/0:0:0:49476 (error no: 13)
01-29 00:11:29.973   502   502 E KeymasterUtils: rsp_header->status: -8
01-29 00:11:29.973   429   429 E keystore2: keystore2::error: In create_operation: Failed to begin operation.
01-29 00:11:29.973   429   429 E keystore2: 
01-29 00:11:29.973   429   429 E keystore2: Caused by:
01-29 00:11:29.973   429   429 E keystore2:     0: In upgrade_keyblob_if_required_with: Upgrade failed.
01-29 00:11:29.973   429   429 E keystore2:     1: Error::Km(ErrorCode(-8))
01-29 00:11:29.973   431   431 E recovery: keystore2 Keystore createOperation returned service specific error: -8
01-29 00:11:30.235     0     0 W subsys-pil-tz soc: qcom,ipa_fws: Direct firmware load for ipa_fws.mdt failed with error -2
```

Once I took `ueventd.rc` from the `vendor` partition instead of the `boot` partition, the correct permissions were added to that device node.

Affter following the guide to include the necessary files, you then attempt to mount `/data`, and then check `logcat` for failing services or missing shared libraries (`dlopen` failed) at runtime. These shared library dependencies can also be determined
statically with `ldcheck`, which is mentioned in the guide. However, this isn't guaranteed to find every dependency.

For example,

```
01-01 15:44:28.735 668 668 E QSEECOMD: : Init dlopen(librpmb.so, RLTD_NOW) is failed.... dlopen failed: library "librpmb.so" not found
```
which can be fixed by including `librpmb.so` and `libssd.so` to `vendor/lib64`.

Once you see `QSEECOM DAEMON RUNNING` you should be good on the libraries. Some libraries will be dlopened by certain binaries, but aren't actually required for it to run, and those binaries may not even be present in your device's stock firmware.

## Starting the Boot & Health HALs
These HALs are required for decryption, and can be started like so:
```
on boot
    start health-hal-2-1

on post-fs
    start boot-hal-1-1
```
in `init.recovery.qcom.rc`.

We also need the Boot HAL passthrough implementation that the service starts, `vendor/lib64/hw/android.hardware.boot@1.0-impl-1.1-qti.so`, in our tree.

## Other required changes
It's also important to set the following in `BoardConfig.mk`
```
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
```
but I can't remember the reason why this is needed.

This device also needed the `TW_PREPARE_DATA_MEDIA_EARLY := true` option to be set.

I also set these, but am not sure if they're necessary:
```
PRODUCT_SHIPPING_API_LEVEL := 30
PRODUCT_TARGET_VNDK_VERSION := 30
```

# QOL improvements
We can tell TWRP where to look for the battery percentage and CPU temperature:
```
TW_CUSTOM_CPU_TEMP_PATH := /sys/devices/virtual/thermal/thermal_zone28/temp
TW_CUSTOM_BATTERY_PATH := /sys/class/power_supply/qcom_battery/capacity
```

and include our boot partition in `system/etc/twrp.flags` so that TWRP can be installed in place from a temporary `fastboot boot`:
```
/boot			emmc	/dev/block/bootdevice/by-name/boot									flags=slotselect
```

That's it! We now have a working TWRP build for the Moto G50. I've skipped, combined, or re-ordered some steps from the order I performed them in during bringup to make this post simpler, shorter, and easier to understand.
If you want to see the full tree, it's available on my [GitHub](https://github.com/robbins/android_device_motorola_ibiza-twrp).

# Misc tips & tricks I've learned (mostly from the TWRP Telegram, shout out Captain Throwback)
- The TWRP build system auto-imports `init.recovery.foo.rc` depending on the value of the `ro.hardware` device property.
- Additional logging can be enabled by adding the following flags:
```
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true
```
- You can test the rest of your decryption setup free from missing library problems by adding the `mounttodecrypt` flag to the `vendor` partition.
- `TWRP_EVENT_LOGGING := true` can help solve touchscreen issues.
