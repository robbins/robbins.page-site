+++
title = "AOSP Porting Log for the Moto G50"
date = "2026-06-19"

[taxonomies]
tags=["aosp", "android"]
+++

# Introduction
## Goals
Android device bringup has always seemed to be a task that many people know how to do, from [Google employees](https://android.googlesource.com/device/google/pantah/+/refs/heads/main) to [device manufacturers](https://github.com/sonyxperiadev/device-sony-columbia) to [hobbyists](https://github.com/LineageOS/android_device_apple_snowcastle), yet,
is niche enough that, in combination with the massive moving target that is Android and resources spread between XDA, Gerrit commits, and a few Telegram groups, feels like the work of a small community of insiders who have it all figured out. [The Android documentation](https://source.android.com) has massively evolved over the years, but they have the task of explaining the architecture as a whole,
and not so much intricacies that seem like they can only be figured out through hands-on experience. 

I wanted to write this article with a few goals in mind:
- Get AOSP running on the Moto G50 (what constitutes 'running' to be determined)
- Document my process and serve as a useful reference/notes
- Learn about different components in AOSP and how they integrate

This won't be the most efficient way of creating a device tree, especially if you need to do this all the time for multiple devices, but I like going through and seeing what happens when certain things are missing, or what configuration is actually required.

I'll assume a general, base level of knowledge about AOSP, and won't explain the absolute fundamentals, but I'm still an absolute beginner myself. For that, you can check out:
- [Gary Explains - Build your own Android custom ROM](https://www.youtube.com/watch?v=99LUjX63LhU), a decade-old video at this point but still a good introduction
- [AOSP Codelab](https://source.android.com/docs/setup/start)
- [Classic XDA post](https://xdaforums.com/t/learn-about-the-repo-tool-manifests-and-local-manifests-and-5-important-tips.2329228/)

A few years ago at this point, I [ported TWRP](@/posts/porting-twrp-to-the-moto-g50.md) to the Moto G50. It's a similar process in that you create a device configuration, but it's much less involved since a recovery image is much simpler. It's also a good read to get a feel for the process, and I'll definitely be pulling information from there.
The next logical step from there was to tackle the task of porting Android to the device.

## References
I'll keep updating this section with useful resources I come across.
- [AlaskaLinuxUser](https://www.youtube.com/@AlaskaLinuxUserAKLU)
- [Android Device Tree Bringup](https://blog.realogs.in/android-device-tree-bringup/)
- [Device Tree Bringup Guide](https://gist.github.com/mvaisakh/1a45694e33584592e8fae37fe29d757d)
- [Zenfone 8 Porting Notes](https://forum.sailfishos.org/t/livecasting-porting-notes-for-zenfone-8/14727)
- [Felix Elsner's Sony AOSP Docs](https://sx.ix5.org/info/)
- [Awesome Android AOSP](https://github.com/Akipe/awesome-android-aosp/blob/main/readme.md)

## Background
Of course, the Moto G50 already runs Android, with lots of code written by the SOC manufacturer, Motorola, etc. to accomplish that. So what are we actually trying to do? At the most basic level, Android device bringup is describing what your device looks like to the build system, so that it can put all the pieces together in the right places to create a build of Android
that will boot on your device. I will be porting Android 12.1 (SDK 32), which is just a minor bump from the current latest software version from Motorola, Android 12 (SDK 31). Android 12 is about 5 years old at this point, and there has been some major changes in the way Android is architected compared to the latest Android 17, but it's not so old (pre 8.x Treble, for example) that nothing is relevant anymore.
Porting to newer versions is [totally](https://www.xda-developers.com/cameras-custom-roms-developers-make-hardware-work-without-source-code/) a thing that exists, and is super awesome, but is a new level on top of this. With that said, let's get started!

## Guidelines
- In most cases, if you can skip something and deal with it later, do so. For example, userdata encryption. Much less work is required to boot unencrypted.
- Referring back to the stock ROM, both the unpacked system images and sometimes a live system, will be your best friend.
- Before you have ADB for logs, `/sys/fs/pstore` is invaluable to know what is happening.
- Don't even consider doing bringup without SELinux set to permissive.

# Gathering Device Information
I covered this in my [TWRP port](@/posts/porting-twrp-to-the-moto-g50.md), but a shortlist of important information:
- Stock ROM system images
- `logcat` & `dmesg` from stock during boot
- The output of `mount`
- The output of `/dev/block/platform/soc/4804000.ufshc/by-name/`
- Contents of `/linkerconfig/ld.conf.txt`
- Contents of `build.prop` (and the various instances of it in `system`, `vendor`, `product`, etc.)
- The output of `fastboot getvar all` (in bootloader fastboot and userspace fastboot)

The actual contents of this post might not be so structured as I try things, investigate logs, and try more things. But I hope it can be helpful in showing the process and what goes wrong when you're missing certain things. I'll try to give accurate headers though.

# Adding a new device
We can follow the [AOSP docs](https://source.android.com/docs/setup/create/new-device) to create the initial makefiles. My device's codename is `ibiza`, so that's what I'll use as the board/device name.

{% detail(title="Initial makefiles", default_open=false) %}
```Make,name=AndroidProducts.mk
PRODUCT_MAKEFILES := \
	$(LOCAL_DIR)/aosp_ibiza.mk

COMMON_LUNCH_CHOICES := \
	aosp_ibiza-eng
```
```Make,name=aosp_ibiza.mk
# Inherit from the common Open Source product configuration
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base_telephony.mk)

PRODUCT_NAME := aosp_ibiza
PRODUCT_DEVICE := ibiza
PRODUCT_BRAND := Android
PRODUCT_MODEL := AOSP on sdm4350
PRODUCT_MANUFACTURER := Moto

$(call inherit-product, device/motorola/ibiza/device-ibiza.mk)

PRODUCT_PACKAGES += \
    Launcher3QuickStep

```
```Make,name=BoardConfig.mk
TARGET_BOOTLOADER_BOARD_NAME = ibiza
```
```Make,name=device-ibiza.mk
PRODUCT_SHIPPING_API_LEVEL := 30
```
{% end %}

We now get:
```Bash
> lunch aosp_ibiza-eng
build/make/core/board_config.mk:193: error: Target architectures not defined by board config: device/motorola/ibiza/BoardConfig.mk.
```

The contents of this doesn't matter so much, as we'll have lots to add later.

## Defining architectures
The SDM4350 has Kryo cores, and ARM naming is confusing but we should have at least ARMv8.2-A, and it supports both 32-bit and 64-bit.
{% detail(title="BoardConfig.mk changes", default_open=false) %}
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index 2c70004..a9cc1d5 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -1 +1,14 @@
 TARGET_BOOTLOADER_BOARD_NAME = ibiza
+
+# Identify CPU architecture & ABI
+TARGET_ARCH := arm64
+TARGET_ARCH_VARIANT := armv8-2a
+TARGET_CPU_ABI := arm64-v8a
+TARGET_CPU_VARIANT := generic
+TARGET_CPU_VARIANT_RUNTIME := kryo
+TARGET_2ND_ARCH := arm
+TARGET_2ND_ARCH_VARIANT := armv8-a
+TARGET_2ND_CPU_ABI := armeabi-v7a
+TARGET_2ND_CPU_ABI2 := armeabi
+TARGET_2ND_CPU_VARIANT := generic
+TARGET_2ND_CPU_VARIANT_RUNTIME := kryo
```
{% end %}

and we can lunch successfully:
{% detail(title="lunch aosp_ibiza-eng", default_open=false) %}
```Bash
============================================
PLATFORM_VERSION_CODENAME=REL
PLATFORM_VERSION=12
TARGET_PRODUCT=aosp_ibiza
TARGET_BUILD_VARIANT=eng
TARGET_BUILD_TYPE=release
TARGET_ARCH=arm64
TARGET_ARCH_VARIANT=armv8-2a
TARGET_CPU_VARIANT=generic
TARGET_2ND_ARCH=arm
TARGET_2ND_ARCH_VARIANT=armv8-a
TARGET_2ND_CPU_VARIANT=generic
HOST_ARCH=x86_64
HOST_2ND_ARCH=x86
HOST_OS=linux
HOST_OS_EXTRA=Linux-6.18.26-x86_64-NixOS-26.05-(Yarara)
HOST_CROSS_OS=windows
HOST_CROSS_ARCH=x86
HOST_CROSS_2ND_ARCH=x86_64
HOST_BUILD_TYPE=release
BUILD_ID=SP2A.220505.008
OUT_DIR=out
============================================
```
{% end %}

and then `m`:
```Bash
FAILED: ninja: 'out/target/product/ibiza/kernel', needed by 'out/target/product/ibiza/obj/PACKAGING/check_vintf_all_intermediates/kernel_configs.txt', missing and no known rule to make it
```

## Using prebuilt kernel
Motorola does publish [kernel source](https://github.com/MotorolaMobilityLLC/kernel-msm/releases/tag/MMI-S1RFS32.27-25-12) for this device, but we can simply use a prebuilt kernel by extracting it from the stock `boot.img`:
```Bash
> unpack_bootimg --boot_img boot_a.img --out boot_stock --format=mkbootimg | tee mkbootimg_args
--header_version 3 --os_version 11.0.0 --os_patch_level 2023-05 --kernel boot_stock/kernel --ramdisk boot_stock/ramdisk --cmdline ''
> file boot_stock/kernel
boot_stock/kernel: Linux kernel ARM64 boot executable Image, little-endian, 4K pages
```

We get some information here for mkbootimg arguments, but the majority of device-specific information will be in the `vendor_boot.img` instead since our device [launched with Android 11](https://source.android.com/docs/core/architecture/partitions/vendor-boot-partitions).
Let's add our stock kernel by copying it directly to the `out/target/product/ibiza` directory where it was looked for.

{% detail(title="Adding stock kernel prebuilt", default_open=false) %}
```diff
diff --git a/device-ibiza.mk b/device-ibiza.mk
index afc954f..addf8f6 100644
--- a/device-ibiza.mk
+++ b/device-ibiza.mk
@@ -1 +1,6 @@
 PRODUCT_SHIPPING_API_LEVEL := 30
+
+# Prebuilt kernel
+TARGET_PREBUILT_KERNEL := $(LOCAL_PATH)/prebuilt/kernel
+PRODUCT_COPY_FILES += \
+	$(TARGET_PREBUILT_KERNEL):kernel
diff --git a/prebuilt/kernel b/prebuilt/kernel
new file mode 100644
index 0000000..c340a88
Binary files /dev/null and b/prebuilt/kernel differ
```
{% end %}

# VINTF shenanigans
## Device manifest
We now get an error about a missing VINTF manifest:
{% detail(title="Error: VINTF manifest", default_open=false) %}
```Bash
FAILED: out/target/product/ibiza/obj/PACKAGING/check_vintf_all_intermediates/check_vintf_vendor.log
/bin/bash -c "( out/host/linux-x86/bin/checkvintf --check-one --dirmap /vendor:out/target/product/ibiza/system/vendor --property ro.boot.product.vendor.sku= > out/target/product/ibiza/obj/PACKAGING/check_vintf_all_intermediates/check_vintf_vendor.log 2>&1 ) || ( cat out/target/product/ibiza/obj/PACKAGING/check_vintf_all_intermediates/check_vintf_vendor.log && exit 1 )"
checkvintf I 06-20 01:07:48  1113  1113 check_vintf.cpp:529] Checking vendor manifest.
checkvintf I 06-20 01:07:48  1113  1113 VintfObject.cpp:58] getDeviceHalManifest: Reading VINTF information.
checkvintf I 06-20 01:07:48  1113  1113 check_vintf.cpp:79] Sysprop ro.boot.product.vendor.sku=
checkvintf I 06-20 01:07:48  1113  1113 HostFileSystem.cpp:43] Fetch 'out/target/product/ibiza/system/vendor/etc/vintf/manifest.xml': NAME_NOT_FOUND
checkvintf I 06-20 01:07:48  1113  1113 check_vintf.cpp:76] Sysprop ro.boot.product.hardware.sku is missing, default to ''
checkvintf I 06-20 01:07:48  1113  1113 HostFileSystem.cpp:43] Fetch 'out/target/product/ibiza/system/vendor/manifest.xml': NAME_NOT_FOUND
checkvintf E 06-20 01:07:48  1113  1113 VintfObject.cpp:68] getDeviceHalManifest: status from fetching VINTF information: -2
checkvintf E 06-20 01:07:48  1113  1113 VintfObject.cpp:69] getDeviceHalManifest: -2 VINTF parse error: Cannot read out/target/product/ibiza/system/vendor/manifest.xml: No such file or directory
checkvintf E 06-20 01:07:48  1113  1113 check_vintf.cpp:532] Cannot fetch vendor manifest.
checkvintf I 06-20 01:07:48  1113  1113 check_vintf.cpp:535] Checking vendor matrix.
checkvintf I 06-20 01:07:48  1113  1113 VintfObject.cpp:58] getDeviceCompatibilityMatrix: Reading VINTF information.
checkvintf I 06-20 01:07:48  1113  1113 HostFileSystem.cpp:43] Fetch 'out/target/product/ibiza/system/vendor/etc/vintf/compatibility_matrix.xml': OK
checkvintf I 06-20 01:07:48  1113  1113 VintfObject.cpp:64] getDeviceCompatibilityMatrix: Successfully processed VINTF information
```
{% end %}

According to the [VINTF documentation](https://source.android.com/docs/core/architecture/vintf/objects), there is the framework manifest (in the `system` partition which is defined by AOSP), and the device manifest which is vendor + ODM manifest.
The stock ROM has the following files:
```Bash
# ODM manifests
vendor_a_img/odm/etc/vintf/manifest_n.xml
vendor_a_img/odm/etc/vintf/manifest_dn.xml
vendor_a_img/odm/etc/vintf/manifest_d.xml
vendor_a_img/odm/etc/vintf/manifest_b.xml
vendor_a_img/etc/vintf/manifest/manifest_IMoto_Fingerprint.xml
vendor_a_img/etc/vintf/manifest/manifest_android.hardware.drm@1.3-service.clearkey.xml
vendor_a_img/etc/vintf/manifest/c2_manifest_vendor.xml
vendor_a_img/etc/vintf/manifest/manifest.xml # Unknown, but we don't want this one
vendor_a_img/etc/vintf/manifest/manifest_android.hardware.drm@1.3-service.widevine.xml
vendor_a_img/etc/vintf/manifest.xml # Device manifest
system_a_img/system/etc/vintf/manifest.xml # Framework manifest
system_a_img/system/etc/vintf/manifest/manifest_media_c2_software.xml
system_a_img/system/etc/vintf/manifest/manifest_android.frameworks.cameraservice.service@2.2.xml
```

We can see 4 ODM manifests, and the device and framework manifests. We want the device manifest, which defines which HALs are implemented by the device.
```
> head vendor_a_img/etc/vintf/manifest.xml
<!--
    Input:
        manifest.xml
        manifest.xml
        manifest.xml
        manifest.xml
-->
<manifest version="2.0" type="device" target-level="5">
    <hal format="hidl">
        <name>android.hardware.audio</name>
```

{% detail(title="Adding VINTF manifest", default_open=false) %}
```diff
diff --git a/device-ibiza.mk b/device-ibiza.mk
index ed7b6ea..5112205 100644
--- a/device-ibiza.mk
+++ b/device-ibiza.mk
@@ -6,7 +6,3 @@ PRODUCT_SHIPPING_API_LEVEL := 30
 TARGET_PREBUILT_KERNEL := $(LOCAL_PATH)/prebuilt/kernel
 PRODUCT_COPY_FILES += \
 	$(TARGET_PREBUILT_KERNEL):kernel
+
+# VINTF
+## Device manifest (from vendor)
+DEVICE_MANIFEST_FILE := $(LOCAL_PATH)/vintf/manifest.xml
```
{% end %}

## Sepolicy version
Next, we get this error relating to the sepolicy verson:
{% detail(title="Error: VINTF manifest sepolicy", default_open=false) %}
```Bash
FAILED: out/target/product/ibiza/gen/ETC/vendor_manifest.xml_intermediates/manifest.xml
/bin/bash -c "BOARD_SEPOLICY_VERS=32.0 	PRODUCT_ENFORCE_VINTF_MANIFEST=true 	PRODUCT_SHIPPING_API_LEVEL=30 	out/host/linux-x86/bin/assemble_vintf -o out/target/product/ibiza/gen/ETC/vendor_manifest.xml_intermediates/manifest.xml 		-i device/motorola/ibiza/vintf/manifest.xml"
Cannot override existing value 30.0 with BOARD_SEPOLICY_VERS (which is 32.0).
```
{% end %}

This line will be added automatically to our device manifest by the build system (check `out/target/product/ibiza/vendor/etc/manifest.xml`), so we can drop this line since we don't want to do anything SELinux related at this point.
{% detail(title="Remove the key", default_open=false) %}
```diff
diff --git a/vintf/manifest.xml b/vintf/manifest.xml
index 0554f84..f370266 100644
--- a/vintf/manifest.xml
+++ b/vintf/manifest.xml
@@ -657,5 +657,8 @@
         </interface>
         <fqname>@1.0::IQspmhal/default</fqname>
     </hal>
-    <sepolicy>
-        <version>30.0</version>
-    </sepolicy>
     <kernel target-level="5"/>
 </manifest>
 ```
{% end %}

## Missing HALs
Next, we get this error from `check_vintf`:
{% detail(title="Error: check_vintf", default_open=false) %}
```Bash
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:388] The following HALs in device manifest are not declared in FCM <= level 5:
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   android.hardware.radio@1.2::ISap/slot2
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   com.dsi.ant@1.0::IAnt/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   com.motorola.hardware.display.panel@1.0::IDisplayPanel/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   com.qualcomm.qti.dpm.api@1.0::IdpmQmi/dpmQmiService
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   com.qualcomm.qti.imscmservice@2.2::IImsCmService/qti.ims.connectionmanagerservice
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   com.qualcomm.qti.uceservice@2.3::IUceService/com.qualcomm.qti.uceservice
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   motorola.hardware.camera.imgtuner@1.0::IImageTuning/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   motorola.hardware.fdrcontrol@1.2::IFdrControl/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   motorola.hardware.health.storage@1.0::IMotStorage/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   motorola.hardware.health@2.0::IMotHealth/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   motorola.hardware.wifi.supplicant@1.1::ISupplicantMot/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.nxp.nxpnfc@2.0::INxpNfc/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.nxp.nxpnfclegacy@1.0::INxpNfcLegacy/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.data.factory@2.2::IFactory/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.alarm@1.0::IAlarm/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.bluetooth_audio@2.0::IBluetoothAudioProvidersFactory/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.bluetooth_sar@1.1::IBluetoothSar/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.btconfigstore@2.0::IBTConfigStore/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.cacert@1.0::IService/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.camera.postproc@1.0::IPostProcService/camerapostprocservice
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.capabilityconfigstore@1.0::ICapabilityConfigStore/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.data.connection@1.1::IDataConnection/slot1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.data.connection@1.1::IDataConnection/slot2
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.data.latency@1.0::ILinkLatency/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.dsp@1.0::IDspService/dspservice
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.eid@1.0::IEid/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.embmssl@1.1::IEmbms/embmsslServer0
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.fm@1.0::IFmHci/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.perf@2.2::IPerf/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.am@1.0::IQcRilAudio/slot1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.am@1.0::IQcRilAudio/slot2
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.ims@1.7::IImsRadio/imsradio0
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.ims@1.7::IImsRadio/imsradio1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.internal.deviceinfo@1.0::IDeviceInfo/deviceinfo
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.lpa@1.1::IUimLpa/UimLpa0
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.lpa@1.1::IUimLpa/UimLpa1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.qcrilhook@1.0::IQtiOemHook/oemhook0
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.qcrilhook@1.0::IQtiOemHook/oemhook1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.qtiradio@1.0::IQtiRadio/slot1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.qtiradio@1.0::IQtiRadio/slot2
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.qtiradio@2.6::IQtiRadio/slot1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.qtiradio@2.6::IQtiRadio/slot2
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.uim@1.2::IUim/Uim0
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.uim@1.2::IUim/Uim1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.uim_remote_client@1.0::IUimRemoteServiceClient/uimRemoteClient0
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.uim_remote_client@1.0::IUimRemoteServiceClient/uimRemoteClient1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.uim_remote_server@1.0::IUimRemoteServiceServer/uimRemoteServer0
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.radio.uim_remote_server@1.0::IUimRemoteServiceServer/uimRemoteServer1
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.sensorscalibrate@1.0::ISensorsCalibrate/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.soter@1.0::ISoter/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.hardware.wifi.wifilearner@1.0::IWifiStats/wifiStats
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.ims.callinfo@1.0::IService/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.ims.factory@1.1::IImsFactory/default
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.imsrtpservice@3.0::IRTPService/imsrtpservice
checkvintf I 06-20 01:51:14 52453 52453 check_vintf.cpp:391]   vendor.qti.qspmhal@1.0::IQspmhal/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] files are incompatible: Device manifest and framework compatibility matrix are incompatible: HALs incompatible. Matrix level = 5. Manifest level = 5. The following requirements are not met:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] android.hardware.graphics.allocator:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     required:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]         @2.0::IAllocator/default OR
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]         @3.0::IAllocator/default OR
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]         @4.0::IAllocator/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     provided:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] android.hardware.graphics.composer:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     required: @2.1-4::IComposer/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     provided:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] android.hardware.graphics.mapper:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     required:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]         @2.1::IMapper/default OR
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]         @3.0::IMapper/default OR
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]         @4.0::IMapper/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     provided:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] android.hardware.health:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     required: @2.1::IHealth/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     provided:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] android.hardware.power:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     required: IPower/default (@1-2)
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     provided:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] The following instances are in the device manifest but not specified in framework compatibility matrix:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     android.hardware.radio@1.2::ISap/slot2
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     com.dsi.ant@1.0::IAnt/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     com.motorola.hardware.display.panel@1.0::IDisplayPanel/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     com.qualcomm.qti.dpm.api@1.0::IdpmQmi/dpmQmiService
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     com.qualcomm.qti.imscmservice@2.2::IImsCmService/qti.ims.connectionmanagerservice
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     com.qualcomm.qti.uceservice@2.3::IUceService/com.qualcomm.qti.uceservice
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     motorola.hardware.camera.imgtuner@1.0::IImageTuning/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     motorola.hardware.fdrcontrol@1.2::IFdrControl/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     motorola.hardware.health.storage@1.0::IMotStorage/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     motorola.hardware.health@2.0::IMotHealth/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     motorola.hardware.wifi.supplicant@1.1::ISupplicantMot/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.nxp.nxpnfc@2.0::INxpNfc/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.nxp.nxpnfclegacy@1.0::INxpNfcLegacy/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.data.factory@2.2::IFactory/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.alarm@1.0::IAlarm/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.bluetooth_audio@2.0::IBluetoothAudioProvidersFactory/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.bluetooth_sar@1.1::IBluetoothSar/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.btconfigstore@2.0::IBTConfigStore/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.cacert@1.0::IService/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.camera.postproc@1.0::IPostProcService/camerapostprocservice
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.capabilityconfigstore@1.0::ICapabilityConfigStore/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.data.connection@1.1::IDataConnection/slot1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.data.connection@1.1::IDataConnection/slot2
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.data.iwlan@1.0::IIWlan/slot2
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.data.latency@1.0::ILinkLatency/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.dsp@1.0::IDspService/dspservice
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.eid@1.0::IEid/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.embmssl@1.1::IEmbms/embmsslServer0
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.fm@1.0::IFmHci/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.perf@2.2::IPerf/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.am@1.0::IQcRilAudio/slot1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.am@1.0::IQcRilAudio/slot2
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.ims@1.7::IImsRadio/imsradio0
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.ims@1.7::IImsRadio/imsradio1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.internal.deviceinfo@1.0::IDeviceInfo/deviceinfo
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.lpa@1.1::IUimLpa/UimLpa0
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.lpa@1.1::IUimLpa/UimLpa1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.qcrilhook@1.0::IQtiOemHook/oemhook0
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.qcrilhook@1.0::IQtiOemHook/oemhook1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.qtiradio@1.0::IQtiRadio/slot1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.qtiradio@1.0::IQtiRadio/slot2
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.qtiradio@2.6::IQtiRadio/slot1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.qtiradio@2.6::IQtiRadio/slot2
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.uim@1.2::IUim/Uim0
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.uim@1.2::IUim/Uim1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.uim_remote_client@1.0::IUimRemoteServiceClient/uimRemoteClient0
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.uim_remote_client@1.0::IUimRemoteServiceClient/uimRemoteClient1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.uim_remote_server@1.0::IUimRemoteServiceServer/uimRemoteServer0
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.radio.uim_remote_server@1.0::IUimRemoteServiceServer/uimRemoteServer1
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.sensorscalibrate@1.0::ISensorsCalibrate/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.soter@1.0::ISoter/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.hardware.wifi.wifilearner@1.0::IWifiStats/wifiStats
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.ims.callinfo@1.0::IService/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.ims.factory@1.1::IImsFactory/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.imsrtpservice@3.0::IRTPService/imsrtpservice
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620]     vendor.qti.qspmhal@1.0::IQspmhal/default
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] Suggested fix:
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] 1. Update deprecated HALs to the latest version.
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] 2. Check for any typos in device manifest or framework compatibility matrices with FCM version >= 5.
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] 3. For new platform HALs, add them to any framework compatibility matrix with FCM version >= 5 where applicable.
checkvintf E 06-20 01:51:14 52453 52453 check_vintf.cpp:620] 4. For device-specific HALs, add to DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE or DEVICE_PRODUCT_COMPATIBILITY_MATRIX_FILE.: Success
```
{% end %}

We're hitting this error because we've defined `PRODUCT_SHIPPING_API_LEVEL := 30`, and we could skip that and add these HALs later since our tree is still extremely barebones, but we may as well just add them now as well.

The HALs that it believes are 'incompatible' are because nothing was provided - these HALs and their VINTF fragments are provided by either the AOSP packages we can add, such as android.hardware.health, or prebuilt blobs from Qualcomm, such as android.hardware.graphics.mapper, whose VINTF fragments exist in vendor/vintf/manifest on the stock ROM.
The other HALs that aren't in the FCM are because they are entirely custom and don't exist in AOSP at all - we simply need to follow the instructions and add them to `DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE`.

For certain HALs, our stock ROM doesn't have a file exactly matching it, such as "android.hardware.graphics.mapper*", but we can notice that it's listed in the VINTF fragment for `vendor.qti.hardware.display.allocator`:
```XML,name=vendor/etc/vintf/manifest/vendor.qti.hardware.display.allocator-service.xml
<manifest version="1.0" type="device">
    <hal format="hidl">
        <name>android.hardware.graphics.allocator</name>
        <transport>hwbinder</transport>
        <version>3.0</version>
        <version>4.0</version>
        <interface>
            <name>IAllocator</name>
            <instance>default</instance>
        </interface>
    </hal>
</manifest>
```
and so is actually provided by `vendor/bin/hw/vendor.qti.hardware.display.allocator-service`. The vendor partition contains these files:
```
> find . -name "*hardware.display.allocator*"
vendor/bin/hw/vendor.qti.hardware.display.allocator-service
vendor/etc/vintf/manifest/vendor.qti.hardware.display.allocator-service.xml
vendor/etc/init/vendor.qti.hardware.display.allocator-service.rc
vendor/lib/vendor.qti.hardware.display.allocator@3.0.so
vendor/lib/vendor.qti.hardware.display.allocator@1.0.so
vendor/lib/vendor.qti.hardware.display.allocator@4.0.so
vendor/lib64/vendor.qti.hardware.display.allocator@3.0.so
vendor/lib64/vendor.qti.hardware.display.allocator@1.0.so
vendor/lib64/vendor.qti.hardware.display.allocator@4.0.so
```
and since there's no `-impl` file, as well as `hwbinder` transport, this is a fully Binderized HAL with no legacy shim layers. The `-service` is the actual implementation, and the `@x.0.so` files are the HIDL interface libraries.

## Qualcomm Open Source
One option would be to simply include the interface libraries and HAL service as prebuilts, copying them from the `vendor` partition. However, Qualcomm actually publishes the source code for their HIDL definitions and HALs; the HALs, however, still interface with proprietary, closed-source binaries.

The HAL interface libraries are generated directly from HIDL defintions. For example, the AOSP definition for the above HAL is [here](https://cs.android.com/android/platform/superproject/+/android-12.1.0_r27:hardware/interfaces/graphics/allocator/4.0/Android.bp), but we want Qualcomm's in case they've made any changes.
To find the correct tag for our device, we can get our BSP version from `ro.vendor.build.version.qcom=LA.UM.9.16.r1-08500.01-MANNAR.QSSI12.0`. CodeAuroraForum used to be where Qualcomm hosted all their open-source code, but they shut it down in 2023 and migrated the repos to git.codelinaro.org. I don't find it as easy to navigate, so I'll just use the Internet Archive
to find the correct manifest.xml.

Thanks to the [Codeaurora Releases Telegram channel](https://web.telegram.org/k/#@CAFReleases), we can search for our BSP and we find:
```
New CAF release detected!
Chipset: holi 
Tag: LA.UM.9.16.r1-08500.01-MANNAR.QSSI12.0 
Manifest: Vendor | System
Android: 11.00.00 
Security Patch: 2021-10-01
Build ID: RKQ1.211119.001
Kernel Version: 5.4.147 (kernel.lnx.5.4.r3-rel) 
Date: December 17, 2021
```

The vendor manifest is [https://source.codeaurora.org/quic/la/la/vendor/manifest/tree/LA.UM.9.16.r1-08500.01-MANNAR.QSSI12.0.xml](https://source.codeaurora.org/quic/la/la/vendor/manifest/tree/LA.UM.9.16.r1-08500.01-MANNAR.QSSI12.0.xml), matching the BSP version, and the system manifest is [https://source.codeaurora.org/quic/la/la/system/manifest/tree/LA.QSSI.11.0.r1-14100-qssi.0.xml](https://web.archive.org/web/20220424122439/https://source.codeaurora.org/quic/la/la/vendor/manifest/tree/LA.UM.9.16.r1-08500.01-MANNAR.QSSI12.0.xml).
Searching for those pages in the Wayback Machine, we find them:
- [https://web.archive.org/web/20220424122331/https://source.codeaurora.org/quic/la/la/system/manifest/tree/LA.QSSI.11.0.r1-14100-qssi.0.xml](https://web.archive.org/web/20220424122331/https://source.codeaurora.org/quic/la/la/system/manifest/tree/LA.QSSI.11.0.r1-14100-qssi.0.xml)
- [https://web.archive.org/web/20220424122439/https://source.codeaurora.org/quic/la/la/vendor/manifest/tree/LA.UM.9.16.r1-08500.01-MANNAR.QSSI12.0.xml](https://web.archive.org/web/20220424122439/https://source.codeaurora.org/quic/la/la/vendor/manifest/tree/LA.UM.9.16.r1-08500.01-MANNAR.QSSI12.0.xml)

and we get the commit for the `platform/vendor/qcom-opensource/interfaces` repo that contains our HIDL definitions.

We can add this to our local manifest and `repo sync`:
```XML
> cat .repo/local_manifests/nate.xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote fetch="https://git.codelinaro.org/clo/la" name="clo" review="codelinaro.org"/>
  <project name="platform/vendor/qcom-opensource/interfaces" path="vendor/qcom/opensource/interfaces" revision="81001c52bb53fc0d8920d0f21499bb0b51000cb2" upstream="refs/heads/android-vendor-hals.lnx.1.1.r53-rel" remote="clo"/>
</manifest>
```

We see the HIDL interface:
{% detail(title="vendor/qcom/opensource/interfaces/display/allocator/4.0/Android.bp", default_open=false) %}
```python,name=vendor/qcom/opensource/interfaces/display/allocator/4.0/Android.bp
hidl_interface {
    name: "vendor.qti.hardware.display.allocator@4.0",
    root: "vendor.qti.hardware.display",
    system_ext_specific: true,
    srcs: [
        "IQtiAllocator.hal",
    ],
    interfaces: [
        "android.hardware.graphics.allocator@4.0",
        "android.hardware.graphics.common@1.0",
        "android.hardware.graphics.common@1.1",
        "android.hardware.graphics.common@1.2",
        "android.hardware.graphics.mapper@4.0",
        "android.hidl.base@1.0",
    ],
    gen_java: false,
}
```
{% end %}

and looks like Qualcomm hasn't made any additions:
```Java,name=vendor/qcom/opensource/interfaces/display/allocator/4.0/IQtiAllocator.hal
package vendor.qti.hardware.display.allocator@4.0;

import android.hardware.graphics.allocator@4.0::IAllocator;

interface IQtiAllocator extends IAllocator {
};
```

The HAL implementation is in `hardware/qcom/display`, so we first have to remove the AOSP copy:
```xml,name=.repo/local_manifests/nate.xml
  <remove-project name="platform/hardware/qcom/display"/>
  <project name="platform/hardware/qcom/display" path="hardware/qcom/display" revision="f621f656c9ae13ed0156d7ac55cd11e2e6ffafca" upstream="refs/heads/display.lnx.7.0.r3-rel" remote="clo"/>
```

and we have our `cc_binary` definition which builds the service and provides our VINTF fragment `check_vintf` was looking for:
{% detail(title="hardware/qcom/display/gralloc/Android.bp", default_open=false) %}
```python,name=hardware/qcom/display/gralloc/Android.bp
cc_binary {
    name: "vendor.qti.hardware.display.allocator-service",
    defaults: ["qtidisplay_defaults"],
    sanitize: {
        integer_overflow: true,
    },
    vendor: true,
    relative_install_path: "hw",
    header_libs: ["display_headers"],
    shared_libs: [
        "libhidlbase",
        "libqdMetaData",
        "libgrallocutils",
        "libgralloccore",
        "libgralloctypes",
        "vendor.qti.hardware.display.allocator@3.0",
        "vendor.qti.hardware.display.allocator@4.0",
        "vendor.qti.hardware.display.mapper@3.0",
        "vendor.qti.hardware.display.mapper@4.0",
        "android.hardware.graphics.mapper@4.0",
        "android.hardware.graphics.mapper@3.0",
        "android.hardware.graphics.mapper@2.1",
        "android.hardware.graphics.allocator@4.0",
        "android.hardware.graphics.allocator@3.0",
        "vendor.qti.hardware.display.mapperextensions@1.0",
        "vendor.qti.hardware.display.mapperextensions@1.1",
    ],
    cflags: ["-DLOG_TAG=\"qdgralloc\""],
    srcs: [
        "QtiAllocator.cpp",
        "service.cpp",
    ],
    init_rc: ["vendor.qti.hardware.display.allocator-service.rc"],
    vintf_fragments: ["vendor.qti.hardware.display.allocator-service.xml"],
}
```
{% end %}

We also need to add these directories to our [Soong namespaces](https://source.android.com/docs/setup/reference/androidbp#namespace_modules) so that the modules defined within them are visible (because these Android.bp files define a `soong_namespace {}` block), otherwise we'll get unknown target errors.

If we try and build the service now, we'll hit some missing dependency errors. Some of these dependencies, such as `libqdMetaData`, are provided in other Qualcomm repos, and some, like `qti_kernel_headers` (through the `qtidisplay_defaults` module), are generated from the kernel source code (macros, conditionals, etc need to be evaluated). 
Luckily, Motorola publishes this, so we can add that to our local manifest as well.
We also hit some dependencies that rely on Qualcomm proprietary code that we do not have, such as `error: hardware/qcom/display/libmemutils/Android.bp:3:1: module "libmemutils" variant "android_vendor.32_arm64_armv8-2a_shared": source path "vendor/qcom/proprietary/common/inc" does not exist`.
However, we can take `libmemutils.so` as a prebuilt blob, so we can just drop this dependency.

We also get:
```
hardware/qcom/display/gralloc/gr_adreno_info.h:34:10: fatal error: 'display/media/mmm_color_fmt.h' file not found
hardware/qcom/display/gralloc/gr_allocator.cpp:38:10: fatal error: 'linux/msm_ion.h' file not found
```

because `qtidisplay_defaults` relies on the value of `SOONG_CONFIG_qtidisplay_default` to include `qti_kernel_headers` in `header_libs`:
```python,name=hardware/qcom/display/Android.bp
    soong_config_variables: {
        default: {
            header_libs: ["display_headers", "qti_kernel_headers"],
        },
        headless: {
            header_libs: ["display_headers"],
        },
```

Note that `default` is a variable and is different to `conditions_default`.

The provided build configuration is as follows:
```Make,name=hardware/qcom/display/config/display-product.mk
# Soong Namespace
SOONG_CONFIG_NAMESPACES += qtidisplay

# Soong Keys
SOONG_CONFIG_qtidisplay := drmpp headless llvmsa gralloc4 default

# Soong Values
SOONG_CONFIG_qtidisplay_drmpp := true
SOONG_CONFIG_qtidisplay_headless := false
SOONG_CONFIG_qtidisplay_llvmsa := false
SOONG_CONFIG_qtidisplay_gralloc4 := true
SOONG_CONFIG_qtidisplay_default := true
```

and following this brings in the kernel headers.

We can repeat a similar process for the rest of the missing HALs, just coming across some compiler errors. We'll have more configuration we can use from the included Makefiles in the `config` directories of all these HALs, but we can do that later.

The Power HAL makefile guards against non-QCOM platforms. AOSP `build/core` doesn't have the function used, so I copied it from LineageOS and modified it like so:
```diff
--- a/core/product_config.mk
+++ b/core/product_config.mk
@@ -77,6 +77,11 @@ define find-copy-subdir-files
+define is-vendor-board-qcom
+$(if $(strip $(TARGET_BOARD_PLATFORM) $(QCOM_BOARD_PLATFORMS)),$(filter $(TARGET_BOARD_PLATFORM),$(QCOM_BOARD_PLATFORMS)),\
+  $(error both TARGET_BOARD_PLATFORM=$(TARGET_BOARD_PLATFORM) and QCOM_BOARD_PLATFORMS=$(QCOM_BOARD_PLATFORMS)))
+endef
```

```diff
--- a/Android.mk
+++ b/Android.mk
@@ -1,6 +1,6 @@
-ifeq ($(call is-vendor-board-platform,QCOM),true)
+ifneq ($(call is-vendor-board-qcom),)
```

(`holi` is the codename for our SoC, the Snapdragon 480)

## Device Specific HALs
We can copy our device-specific system FCM from `system_a_img/system/etc/vintf/compatibility_matrix.device.xml` and set `DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE` after dropping the `sepolicy` and `vbmeta` keys.
We see what files it was generated from:
```XML
<!--
    Input:
        moto_framework_compatibility_matrix.xml
        vendor_goodix_product_compatibility_matrix.xml
        framework_compatibility_matrix.xml
        framework_compatibility_matrix.xml
        vendor_framework_compatibility_matrix.xml
-->
```

# First Build Success & Fleshing It Out
We're able to complete a build now, but it was suspiciously quick, and `$OUT` is pretty sparse. Of course, there's lots more configuration that we still need to do. Most of this can be done by examining other device trees, figuring out what platform features your device supports (e.g. A/B partitions, dynamic partitions), and reading the AOSP documentation to see what it says is required
for the Android version you're trying to port.

## A/B updates
Our partition dumps show `_a` and `_b` partitions, so we can follow the [AB docs](https://source.android.com/docs/core/ota/ab/ab_implement#build-variables) to configure it.
We don't have a recovery partition since that's implemented in `boot.img` nowadays, and we can add all the slotted partitions to `AB_OTA_PARTITIONS`.
{% detail(title="A/B configuation", default_open=false) %}
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index 6382dce..00f775e 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -13,7 +13,13 @@ TARGET_2ND_CPU_ABI2 := armeabi
 TARGET_2ND_CPU_VARIANT := generic
 TARGET_2ND_CPU_VARIANT_RUNTIME := kryo

+# A/B updates
+TARGET_NO_RECOVERY := true
+BOARD_USES_RECOVERY_AS_BOOT := true
+
+# QCOM Display HAL
 TARGET_IS_HEADLESS := false

+# QCOM Power HAL (and maybe others)
 TARGET_BOARD_PLATFORM := holi
 QCOM_BOARD_PLATFORMS += holi
diff --git a/device-ibiza.mk b/device-ibiza.mk
index 3e866fd..f670787 100644
--- a/device-ibiza.mk
+++ b/device-ibiza.mk
@@ -29,10 +29,31 @@ SOONG_CONFIG_qtidisplay := headless default
 SOONG_CONFIG_qtidisplay_default := true
 SOONG_CONFIG_qtidisplay_headless := false

+# Health
 PRODUCT_PACKAGES += \
     android.hardware.health@2.1-impl-qti \
     android.hardware.health@2.1-service

+# Power
 PRODUCT_PACKAGES += \
     android.hardware.power-service \
     android.hardware.power-impl
+
+# A/B
+AB_OTA_UPDATER := true
+PRODUCT_PACKAGES += \
+  update_engine \
+  update_verifier
+# Debug builds
+PRODUCT_PACKAGES_DEBUG += update_engine_client
+
+# A/B updatable partitions
+AB_OTA_PARTITIONS := \
+  boot \
+  system \
+  vendor \
+  system_ext \
+  product \
+  dtbo \
+  vbmeta \
+  vbmeta_system
```
{% end %}

## Dynamic partitions
We also have a `super` partition, which means dynamic partition support. `BOARD_SUPER_PARTITION_SIZE` is simply the size of `super.img` in bytes, and `BOARD_MOTOROLA_DYNAMIC_PARTITIONS_SIZE` is `(SUPER_PARTITION_SIZE / 2) - 4194304`. This is all described in the [dynamic partition docs](https://source.android.com/docs/core/ota/dynamic_partitions/implement#implement-dynamic-partitions-new-devices).
On the running device, we see that `/dev/block/bootdevice` is a symlink to `/dev/block/platform/soc/4804000.ufshc/` and set that accordingly.

{% detail(title="A/B configuation", default_open=false) %}
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index 00f775e..696ac86 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -23,3 +23,10 @@ TARGET_IS_HEADLESS := false
 # QCOM Power HAL (and maybe others)
 TARGET_BOARD_PLATFORM := holi
 QCOM_BOARD_PLATFORMS += holi
+
+# Dynamic partitions
+BOARD_SUPER_PARTITION_SIZE := 12884901888
+BOARD_SUPER_PARTITION_GROUPS := motorola_dynamic_partitions
+BOARD_MOTOROLA_DYNAMIC_PARTITIONS_SIZE := 6438256640
+BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product system_ext
+BOARD_KERNEL_CMDLINE += androidboot.boot_devices=soc/4804000.ufshc
diff --git a/device-ibiza.mk b/device-ibiza.mk
index f670787..23884af 100644
--- a/device-ibiza.mk
+++ b/device-ibiza.mk
@@ -57,3 +57,6 @@ AB_OTA_PARTITIONS := \
   dtbo \
   vbmeta \
   vbmeta_system
+
+# Dynamic partitions
+PRODUCT_USE_DYNAMIC_PARTITIONS := true
```
{% end %}

We can now `m` and see a much more reasonable 110k targets.

## Partition Types & Sizes
We didn't specify a boot image size yet:
```
[ 90% 9820/10866] Target boot image from recovery: out/target/product/ibiza/boot.img
FAILED: out/target/product/ibiza/boot.img
/bin/bash -c "(out/host/linux-x86/bin/mkbootimg --kernel out/target/product/ibiza/kernel --ramdisk out/target/product/ibiza/ramdisk-recovery.img  --cmdline \"androidboot.boot_devices=soc/4804000.ufshc buildvariant=eng\" --os_version 12 --os_patch_level 2022-05-05   --output  out/target/product/ibiza/boot.img ) && (size=\$(for i in  out/target/product/ibiza/boot.img; do stat -c \"%s\" \"\$i\" | tr -d '\\n'; echo +; done;echo 0); total=\$(( \$( echo \"\$size\" ) )); printname=\$(echo -n \" out/target/product/ibiza/boot.img\" | tr \" \" +); maxsize=\$((     -0)); if [ \"\$total\" -gt \"\$maxsize\" ]; then echo \"error: \$printname too large (\$total > \$maxsize)\"; false; elif [ \"\$total\" -gt \$((maxsize - 32768)) ]; then echo \"WARNING: \$printname approaching size limit (\$total now; limit \$maxsize)\"; fi )"
error: +out/target/product/ibiza/boot.img too large (50505728 > 0)
```
so we can set `BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296`.

and we need to specify filesystem types, which we can get from our `/etc/fstab.qcom`:
{% detail(title="Error: unknown filesystem type", default_open=false) %}
```
[ 99% 1233/1235] Target system fs image: out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system.img
FAILED: out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system.img
/bin/bash -c "(mkdir -p out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/ out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates && rm -rf out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"system_selinux_fc=out/target/product/ibiza/obj/ETC/file_contexts.bin_intermediates/file_contexts.bin\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"building_system_image=true\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"ext_mkuserimg=mkuserimg_mke2fs\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"extfs_sparse_flag=-s\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"erofs_sparse_flag=-s\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"squashfs_sparse_flag=-s\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"f2fs_sparse_flag=-S\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"verity_disable=true\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"recovery_as_boot=true\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"root_dir=out/target/product/ibiza/root\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"use_dynamic_partition_size=true\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (echo \"skip_fsck=true\" >>  out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt ) && (PATH=out/host/linux-x86/bin/:system/extras/ext4_utils/:\$PATH out/host/linux-x86/bin/build_image out/target/product/ibiza/system out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system_image_info.txt out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system.img out/target/product/ibiza/system || ( mkdir -p \${DIST_DIR}; cp out/target/product/ibiza/installed-files.txt \${DIST_DIR}/installed-files-rescued.txt; exit 1 ) )"
2026-06-23 16:42:38 - build_image.py - ERROR   : Failed to build out/target/product/ibiza/obj/PACKAGING/systemimage_intermediates/system.img from out/target/product/ibiza/system
Traceback (most recent call last):
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/internal/stdlib/runpy.py", line 174, in _run_module_as_main
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/internal/stdlib/runpy.py", line 72, in _run_code
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/__main__.py", line 12, in <module>
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/internal/stdlib/runpy.py", line 174, in _run_module_as_main
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/internal/stdlib/runpy.py", line 72, in _run_code
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/build_image.py", line 943, in <module>
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/build_image.py", line 935, in main
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/build_image.py", line 546, in BuildImage
  File "/aosp/android-12-1-0/out/host/linux-x86/bin/build_image/build_image.py", line 375, in BuildImageMkfs
__main__.BuildImageError: Error: unknown filesystem type:
```
{% end %}

```Make,name=BoardConfig.mk
# Partitions
TARGET_COPY_OUT_SYSTEM := system
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_PRODUCT := product
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR := vendor
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
```

We need `TARGET_COPY_OUT` because `product` and `vendor` are separate partitions (whose contents are in `$OUT/{vendor,product,system_ext}` instead of `$OUT/system/{vendor,product,system_ext}` on older devices).
Make sure to `m installclean` to delete the old directories and force new ones to be created.

## Boot & Vendor Boot Images
From our device's stock ROM, we have both `boot` and `vendor_boot` partitions. The `vendor_boot` partition contains the bulk of the customizations. I go over unpacking them and extracting the ramdisk in my post on [Porting TWRP to the Moto G50](@/posts/porting-twrp-to-the-moto-g50.md). 
I've copied some of that output here:
```Bash
vendor boot image header version: 3
page size: 0x00001000
kernel load address: 0x00008000
ramdisk load address: 0x01000000
vendor command line args: console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0x04C8C000 androidboot.hardware=qcom androidboot.console=ttyMSM0 androidboot.memcg=1 lpm_levels.sleep_disabled=1 video=vfb:640x400,bpp=32,memsize=3072000 msm_rtb.filter=0x237 service_locator.enable=1 androidboot.usbcontroller=4e00000.dwc3 swiotlb=0 loop.max_part=7 cgroup.memory=nokmem,nosocket iptable_raw.raw_before_defrag=1 ip6table_raw.raw_before_defrag=1 firmware_class.path=/vendor/firmware_mnt/image androidboot.hab.csv=18 androidboot.hab.product=ibiza androidboot.hab.cid=50 buildvariant=user
kernel tags load address: 0x00000100
vendor boot image header size: 2112
dtb address: 0x0000000001f00000
```
`unpack_bootimg.py` gives us our offsets, `cmdline`, version, etc. We don't see `kernel base address` in our output, but it's defined in the script as `base + kernel_offset` and since our `kernel load address` is `0x8000` which matches the default `kernel offset`, our base address should simply be `0x0`.
We also need to add `vendor_boot` to `AB_OTA_PARTITIONS`. Finally, we can add our `fstab` from the vendor_boot ramdisk.

{% detail(title="Boot & Vendor Boot Changes", default_open=false) %}
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index a2c924e..788d188 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -1,4 +1,5 @@
 TARGET_BOOTLOADER_BOARD_NAME = ibiza
+PRODUCT_PLATFORM := qcom

 # Identify CPU architecture & ABI
 TARGET_ARCH := arm64
@@ -31,8 +32,21 @@ BOARD_MOTOROLA_DYNAMIC_PARTITIONS_SIZE := 6438256640
 BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product system_ext
 BOARD_KERNEL_CMDLINE += androidboot.boot_devices=soc/4804000.ufshc

-# Boot partition
+# Boot & vendor boot partitions
+BOARD_BOOT_HEADER_VERSION := 3
 BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
+BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
+BOARD_KERNEL_BASE := 0x00000000
+BOARD_KERNEL_PAGESIZE := 4096
+BOARD_KERNEL_OFFSET := 0x00008000
+BOARD_KERNEL_TAGS_OFFSET := 0x00000100
+BOARD_RAMDISK_OFFSET := 0x01000000
+BOARD_MKBOOTIMG_ARGS := --base $(BOARD_KERNEL_BASE) \
+                        --pagesize $(BOARD_KERNEL_PAGESIZE) \
+                        --kernel_offset $(BOARD_KERNEL_OFFSET) \
+                        --ramdisk_offset $(BOARD_RAMDISK_OFFSET) \
+                        --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) \
+                        --header_version $(BOARD_BOOT_HEADER_VERSION) \

 # Partitions
 TARGET_COPY_OUT_SYSTEM := system
@@ -43,3 +57,7 @@ TARGET_COPY_OUT_SYSTEM_EXT := system_ext
 BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
 TARGET_COPY_OUT_VENDOR := vendor
 BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
+
+# Fstab
+PRODUCT_COPY_FILES += \
+        $(LOCAL_PATH)/fstab.hardware:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.$(PRODUCT_PLATFORM)
diff --git a/device-ibiza.mk b/device-ibiza.mk
index 23884af..b09e023 100644
--- a/device-ibiza.mk
+++ b/device-ibiza.mk
@@ -50,6 +50,7 @@ PRODUCT_PACKAGES_DEBUG += update_engine_client
 # A/B updatable partitions
 AB_OTA_PARTITIONS := \
   boot \
+  vendor_boot \
   system \
   vendor \
   system_ext \
```
{% end %}

## Trimming The Fstab Fat
We don't care about userdata encryption or AVB at this point, so let's drop it from our `fstab` to make things easier:
```diff
diff --git a/fstab.hardware b/fstab.hardware
index ce139cb..e12c7c5 100644
--- a/fstab.hardware
+++ b/fstab.hardware
@@ -35,14 +35,14 @@
 # specify MF_CHECK, and must come before any filesystems that do specify MF_CHECK
 
 #<src>                                                 <mnt_point>            <type>  <mnt_flags and options>                            <fs_mgr_flags>
-system                                                  /system                ext4    ro,discard                                 wait,slotselect,avb=vbmeta_system,logical,first_stage_mount,avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey
-system_ext                                              /system_ext            ext4    ro,discard                                 wait,slotselect,avb=vbmeta_system,logical,first_stage_mount
-product                                                 /product               ext4    ro,discard                                 wait,slotselect,avb=vbmeta,logical,first_stage_mount
-vendor                                                  /vendor                ext4    ro,discard                                 wait,slotselect,avb=vbmeta,logical,first_stage_mount
+system                                                  /system                ext4    ro,discard                                 wait,slotselect,logical,first_stage_mount
+system_ext                                              /system_ext            ext4    ro,discard                                 wait,slotselect,logical,first_stage_mount
+product                                                 /product               ext4    ro,discard                                 wait,slotselect,logical,first_stage_mount
+vendor                                                  /vendor                ext4    ro,discard                                 wait,slotselect,logical,first_stage_mount
 /dev/block/by-name/metadata                             /metadata              ext4    noatime,nosuid,nodev,discard,data=ordered,barrier=1  wait,check,formattable,first_stage_mount
 /dev/block/bootdevice/by-name/persist                   /mnt/vendor/persist    ext4    noatime,nosuid,nodev,data=ordered,barrier=1          wait
 /dev/block/bootdevice/by-name/prodpersist               /mnt/product/persist   ext4    noatime,nosuid,nodev,data=ordered,barrier=1          wait,formattable,nofail
-/dev/block/bootdevice/by-name/userdata                  /data                  f2fs    noatime,nosuid,nodev,discard,inlinecrypt,reserve_root=32768,resgid=1065,fsync_mode=nobarrier    latemount,wait,check,formattable,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0,keydirectory=/metadata/vold/metadata_encryption,metadata_encryption=aes-256-xts:wrappedkey_v0,quota,sysfs_path=/sys/devices/platform/soc/4804000.ufshc,reservedsize=128M,checkpoint=fs
+/dev/block/bootdevice/by-name/userdata                  /data                  f2fs    noatime,nosuid,nodev,discard,inlinecrypt,reserve_root=32768,resgid=1065,fsync_mode=nobarrier    latemount,wait,check,formattable,quota,sysfs_path=/sys/devices/platform/soc/4804000.ufshc,reservedsize=128M,checkpoint=fs
 /dev/block/bootdevice/by-name/misc                      /misc                  emmc    defaults                                             defaults
 /devices/platform/soc/4784000.sdhci/mmc_host*           /storage/sdcard1       vfat    nosuid,nodev                                         wait,voldmanaged=sdcard1:auto
 /devices/platform/soc/*.ssusb/*.dwc3/xhci-hcd.*.auto*   /storage/usbotg        vfat    nosuid,nodev                                         wait,voldmanaged=usbotg:auto
```

## DTB & DTBO
To resolve `ValueError: DTB image must not be empty.`, we can specify our prebuilt DTBO from stock and include the DTB from our vendor_boot image
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index 2b69f87..f781a9c 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -34,6 +34,22 @@ BOARD_MOTOROLA_DYNAMIC_PARTITIONS_SIZE := 6438256640
 BOARD_MOTOROLA_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product system_ext
 BOARD_KERNEL_CMDLINE += androidboot.boot_devices=soc/4804000.ufshc

+# Device Tree Blob
+BOARD_USES_DT := true
+BOARD_INCLUDE_DTB_IN_BOOTIMG := true
+BOARD_PREBUILT_DTBIMAGE_DIR := $(LOCAL_PATH)/prebuilt/
+BOARD_PREBUILT_DTBOIMAGE := $(BOARD_PREBUILT_DTBIMAGE_DIR)/dtbo.img
+
 # Boot & vendor boot partitions
 BOARD_BOOT_HEADER_VERSION := 3
 BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
@@ -43,23 +59,17 @@ BOARD_KERNEL_PAGESIZE := 4096
 BOARD_KERNEL_OFFSET := 0x00008000
 BOARD_KERNEL_TAGS_OFFSET := 0x00000100
 BOARD_RAMDISK_OFFSET := 0x01000000
+BOARD_DTB_OFFSET := 0x01f00000
 BOARD_MKBOOTIMG_ARGS := --base $(BOARD_KERNEL_BASE) \
                         --pagesize $(BOARD_KERNEL_PAGESIZE) \
                         --kernel_offset $(BOARD_KERNEL_OFFSET) \
                         --ramdisk_offset $(BOARD_RAMDISK_OFFSET) \
                         --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) \
                         --header_version $(BOARD_BOOT_HEADER_VERSION) \
+                        --dtb $(BOARD_PREBUILT_DTBIMAGE_DIR)/dtb \
+                        --dtb_offset $(BOARD_DTB_OFFSET)
diff --git a/prebuilt/dtb b/prebuilt/dtb
new file mode 100644
index 0000000..9b05c73
Binary files /dev/null and b/prebuilt/dtb differ
diff --git a/prebuilt/dtbo.img b/prebuilt/dtbo.img
new file mode 100644
index 0000000..f98ce93
Binary files /dev/null and b/prebuilt/dtbo.img differ
```

## SELinux Permissive
Finally, we can disable SELinux:
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index f781a9c..d0dd2e8 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -73,3 +73,8 @@ BOARD_MKBOOTIMG_ARGS := --base $(BOARD_KERNEL_BASE) \
 PRODUCT_COPY_FILES += \
         $(LOCAL_PATH)/fstab.hardware:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.$(PRODUCT_PLATFORM)
 
+# SELinux
+BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
+
+# Serial console
+BOARD_KERNEL_CMDLINE += androidboot.console=ttyMSM0,115200n8
```

and we should be at a good point to try a first boot!

# First Flash & Boot
Before we boot the whole system, we can boot into recovery and see if that works first, as it's much simpler. We can flash `boot` and `vendor_boot` and cross our fingers: `fastboot flash boot $OUT/boot.img && fastboot flash vendor_boot $OUT/vendor_boot.img`
Unfortunately, we get stuck on the Motorola boot logo. So we have no display, and no USB access for logs - do we have to debug this blind? Luckily, no.
This is where our previous TWRP build comes in handy. It allows `adb` access, and the kernel stores logs from last boot in RAM at `/sys/fs/pstore`.

## AVB
We see:
```
[    4.0)9846] init: [libfs_avb]Device path no4 found:/dev/block/by-nam%/boot_a
[    4.100106] init: [libfs_avb]avb_slot_verify failed, result: 2
[    4.100127] init: Failed to open AvbHandle for INIT_AVBWVERSION: Lo such file or directory
[    4.120960] init: Could not update logical partition
[    4.121063] init: Could not update logical partition
```

We can disable AVB by flashing the `vbmeta` and `vbmeta_system` partitions with the `--disable-verity --disable-verification` flags passed to `fastboot` and try again:

## Fstab /system mount
Now we see a better error:
```
[    2.022587] init: [libfs_mgb]ReadFstabFromFil$():`cannot open file: '/etc,recovery.fsta`': No such file or directory
[    2.089848] init: [libfs_mgr]ReadFstabFromFile(): cannot open file: '/etc.recovery.fstaB': o such file or directory
[    2.089863] init: Could not read deFa5lt fstab
[    2.089980] init: Could not find mount entry for /system
```

Yeah, the RAM gets a little corrupted sometimes - I don't know why that is, but it's interesting.

Our stock boot image has a minimal fstab at `ramdisk/system/etc/recovery.fstab` (for example, it doesn't need to decrypt and mount userdata), so let's use it:

This installs our fstab at `$OUT/recovery/root/system/etc/recovery.fstab` (TARGET_RECOVERY_ROOT_OUT), whereas before we only had it in `./vendor_ramdisk/first_stage_ramdisk/fstab.qcom`, and indeed this is one of the places it looks:
```cpp,name=system/fs/fs_mgr/libfstab/fstab.cpp
std::string GetFstabPath() {
    if (InRecovery()) {
        return GetRecoveryFstabPath();
    }
    for (const char* prop : {"fstab_suffix", "hardware", "hardware.platform"}) {
        std::string suffix;

        if (!fs_mgr_get_boot_config(prop, &suffix)) continue;

        for (const char* prefix : {// late-boot/post-boot locations
                                   "/odm/etc/fstab.", "/vendor/etc/fstab.",
                                   // early boot locations
                                   "/system/etc/fstab.", "/first_stage_ramdisk/system/etc/fstab.",
                                   "/fstab.", "/first_stage_ramdisk/fstab."}) {
            std::string fstab_path = prefix + suffix;
            if (access(fstab_path.c_str(), F_OK) == 0) {
                return fstab_path;
            }
        }
    }

    return "";
}
```

## Recovery boots!
This time, the Motorola boot logo is replaced after a few seconds with... a black screen. I ran into this when porting TWRP - we need to set `TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888`. And - recovery boots!
{{ figure(src="./aosp_recovery.jpeg", width=300, height=50, caption="AOSP recovery") }}

# ADB, Userspace Fastboot, Misc. Improvements to Recovery
Before we boot the system, let's fix some things with the recovery first, such as ADB so we don't have to keep using TWRP.

We can follow the init scripts from `boot.img` such as `ramdisk/init.recovery.qcom.rc` to configure the dual-role USB controller in device mode, and enable `configfs` to configure it. The AOSP scripts will set up the ADB and Fastboot FunctionFS interfaces.
However, it sets a lot of "cosmetic" properties and properties that the AOSP default `init.rc` already sets, so we can get away with a very minimal setup.
The AOSP init script also looks for our init script based on `androidboot.hardware=qcom` so we need to pass that on the `cmdline`. Finally, we need to install the `fastbootd` binary for flashing dynamic partitions in recovery.

```
> lsusb
Bus 001 Device 059: ID 18d1:d001 Google Inc. Nexus 4 (fastboot)
<enter fastboot>
> lsusb
Bus 001 Device 060: ID 18d1:4ee0 Google Inc. Nexus/Pixel Device (fastboot)
```

Ok, maybe we could've kept the VID/PID part of the gadget configuration, but now we have a good environment for debugging system boot failures, and for flashing the rest of the system. 
Let's make sure we mount `pstore` since it doesn't seem to be mounted by default by adding that to the `on init` trigger, and we can also set some other useful `cmdline` parameters: `BOARD_KERNEL_CMDLINE += printk.devkmsg=on androidboot.init_fatal_panic=true printk.always_kmsg_dump=1 androidboot.init_fatal_reboot_target=recovery`.

## Fixing factory reset
We also need the following so that binaries like `make_f2fs` are installed.
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index d340863..a041a5b 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -91,3 +91,8 @@ BOARD_KERNEL_CMDLINE += androidboot.usbcontroller=4e00000.dwc3
 
 # Debugging
 BOARD_KERNEL_CMDLINE += printk.devkmsg=on androidboot.init_fatal_panic=true printk.always_kmsg_dump=1 androidboot.init_fatal_reboot_target=recovery
+
+# Userdata Partition
+TARGET_USERIMAGES_USE_F2FS := true
+TARGET_USERIMAGES_USE_EXT4 := true
+BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
```

# First (Real) System Flash & Boot
```Bash
> fastboot flash boot boot.img && fastboot flash vendor_boot vendor_boot.img
> fastboot reboot fastboot # this command makes a lot of sense and totally isn't confusing
> fastboot flash system_a $OUT/system.img && fastboot flash vendor_a $OUT/vendor.img && fastboot flash product_a $OUT/product.img && fastboot flash system_ext_a $OUT/system_ext.img
```
And after wiping `/data` for good measrue, we get the Motorola boot logo followed by a reset. Pulling `/sys/fs/pstore`, we see:

```
[    2.94686] Init: [libfsWmgr]__moult(smurce=/dev/block/dm-1,pargat=/system,type=ext4)=0: Success
[    2.961369] init: Unable to move m/unt at /metadata': o such fihe or dire�tory
[    2.969132] InIt: InatDatalReboot: sIgnal 6
[    2.97975] init: IniTFatalReboot: Faildd to unwind callstack.
[    2.992191] iji4: InitFatalReboot: Trigger crash
[    3.004578] init: IfitFatalReBoot: Sys-Rq faileD to crash the system; fallback to exit().
```

## Unable to move mount at /metadata
`/metadata` is in our fstab, and it looks like it's in `/proc/mounts`:
```cpp,name=system/core/init/switch_root.cpp
void SwitchRoot(const std::string& new_root) {
    auto mounts = GetMounts(new_root);

    LOG(INFO) << "Switching root to '" << new_root << "'";

    for (const auto& mount_path : mounts) {
        auto new_mount_path = new_root + mount_path;
        mkdir(new_mount_path.c_str(), 0755);
        if (mount(mount_path.c_str(), new_mount_path.c_str(), nullptr, MS_MOVE, nullptr) != 0) {
            PLOG(FATAL) << "Unable to move mount at '" << mount_path << "'";
        }
    }
    ...
}
std::vector<std::string> GetMounts(const std::string& new_root) {
    auto fp = std::unique_ptr<std::FILE, decltype(&endmntent)>{setmntent("/proc/mounts", "re"),
                                                               endmntent};
    ...
}
```

I'm not sure if that's referring to the source directory or the mount point directory - I guess it'd have to be the mount point since the mount souce directory exists, and for some reason this is solved by setting `BOARD_USES_METADATA_PARTITION := true`. This flag creates:
```
./root/metadata
./ramdisk/metadata
./recovery/root/metadata
```
but I'm not exactly sure why this fixes it. [AOSP docs on metadata encryption](https://source.android.com/docs/security/features/encryption/metadata#set-up-metadata-filesystem) back me up though.

## Could not read default fstab
We're making some progress booting.
```
[    1.999740] ufshcd-qcom 4804000.ufshc: *** This is drivers/scsi/ufs'ufshcD.c ***
[    3.162906Y init: Cou,d not read dedault fstab
S    0.164444] i.it: ctartings%rvice 'servicemanaggr'...
[    4.171630] init: starting Service 'hwservice=anager'...
[    4.295077] init: starting rervice 'vold'...
[    4.80 242]0)nit: CjmManD 'chlod 077 /da�!' ActiOn=po3t-fs-``da (/cpstEm/etc/Init/hw/Anit.2c:6"9) took 0ms and faile`: bb(eodat() Fa)ded:Read-kn,y `ihe system
```

Seems like `/data` is read-only, which makes sense if we've switched root to `/system`, which is mounted read-only. So without an fstab to mount `userdata` on top of `/data`, we can't write to it.
If we recall back to earlier, one of the locations is `/vendor/etc/fstab`, so let's drop it in there. We also have [user-data checkpointing](https://source.android.com/docs/core/ota/user-data-checkpoint) in our fstab, so we can follow those docs to mount a subset of partitions early, and then `userdata` late, as well as the metadata encryption docs (even though we're running with encryption disabled for now).

{% detail(title="Fstab & Init changes", default_open=false) %}
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index 3464ea0..e11710b 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -99,3 +99,4 @@ BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
 
 # Metadata encryption
 BOARD_USES_METADATA_PARTITION := true
+BOARD_ROOT_EXTRA_FOLDERS := metadata
diff --git a/device-ibiza.mk b/device-ibiza.mk
index 17aa4d9..6b590fc 100644
--- a/device-ibiza.mk
+++ b/device-ibiza.mk
@@ -7,6 +7,8 @@ TARGET_PREBUILT_KERNEL := $(LOCAL_PATH)/prebuilt/kernel
 PRODUCT_COPY_FILES += \
 	$(TARGET_PREBUILT_KERNEL):kernel
 
+PRODUCT_PLATFORM := qcom
+
 # VINTF
 ## Device manifest (from vendor)
 DEVICE_MANIFEST_FILE := $(LOCAL_PATH)/vintf/manifest.xml
@@ -73,3 +75,7 @@ PRODUCT_COPY_FILES += \
 # System init
 PRODUCT_COPY_FILES += \
         $(LOCAL_PATH)/init/init.hardware.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.qcom.rc
+
+# Mount partitions early (first-stage-mount)
+PRODUCT_COPY_FILES += \
+        $(LOCAL_PATH)/fstab.hardware:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.$(PRODUCT_PLATFORM)
diff --git a/init/init.hardware.rc b/init/init.hardware.rc
index e48ead6..66e4492 100644
--- a/init/init.hardware.rc
+++ b/init/init.hardware.rc
@@ -6,3 +6,16 @@ on early-init
     loglevel 6
     setprop sys.init_log_level 6
     write /proc/sys/kernel/printk 7
+
+on init
+    wait /dev/block/platform/soc/${ro.boot.bootdevice}
+    symlink /dev/block/platform/soc/${ro.boot.bootdevice} /dev/block/bootdevice
+
+on early-fs
+    start vold
+
+on fs
+    mount_all /vendor/etc/fstab.${ro.boot.hardware} --early
+
+on late-fs
+    mount_all /vendor/etc/fstab.${ro.boot.hardware} --late

```
{% end %}

## Error getting bootctrl module
Our next error is:
```
2 [   13.007193] update_fepifier: Started with arg 1: nonencrypted
    1 [   13.013261] binder: 516:516 ioctl 40046210 7fd0cacc24 returned -22
  498 [   13.022223] update_verifier: Error getting bootctrl module.
    1 [   13.028473] ini|: Received sys.p/WeBctl=^GReboot' from pid: 516 (/system/bin/update_verifier)
```

and the source is pretty clear on this one:
```cpp
const auto module = android::hal::BootControlClient::WaitForService();
if (module == nullptr) {
  LOG(ERROR) << "Error getting bootctrl module.";
  return reboot_device();
}
```

so we just need to add (we can take it from AOSP, don't need anything special from the Qualcomm impl.):
```diff
diff --git a/device-ibiza.mk b/device-ibiza.mk
index 6b590fc..a840aec 100644
--- a/device-ibiza.mk
+++ b/device-ibiza.mk
@@ -79,3 +79,7 @@ PRODUCT_COPY_FILES += \
 # Mount partitions early (first-stage-mount)
 PRODUCT_COPY_FILES += \
         $(LOCAL_PATH)/fstab.hardware:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.$(PRODUCT_PLATFORM)
+
+# Boot HAL
+PRODUCT_PACKAGES += android.hardware.boot@1.1-service
+PRODUCT_PACKAGES += android.hardware.boot@1.1-impl

```

## SELinux domain transition workaround
Now we're in a better place, as the device doesn't reboot anymore, but we see:
```
[   23.535277] )nit: Dile /vendor/bin/hw/vendor.ati.hap$ware.display®composer-service (labeled "u:object_r:vendmr_filg:s0") has incorreCt label or no domain transition from u:r:init:s0 to another SELinux domain defined. Have you configured your service correctly? https://source.android.com/security/selinux/device-policy#label_new_services_afd_a$dress_denials
```

We're not even going to get into SELinux right now, so let's cherry-pick [https://review.lineageos.org/c/LineageOS/android_system_core/+/368710](https://review.lineageos.org/c/LineageOS/android_system_core/+/368710) from LineageOS to ensure that the services will still be started even if they don't have a domain.

## Fixing ADB
I'm getting real tired of rebooting into recovery and pulling `sys/fs/pstore` every time I want to look at the logs, and the log corruption makes it hard to grep. Let's set up ADB for the 2nd time. This time, we need a bit more configuration, and we also need to override `sys.usb.controller` with our real USB controller instead of the dummy host controller driver since `CONFIG_USB_DUMMY_HCD=y` is set.
```diff
diff --git a/init/init.hardware.rc b/init/init.hardware.rc
index 66e4492..e36d697 100644
--- a/init/init.hardware.rc
+++ b/init/init.hardware.rc
@@ -19,3 +19,31 @@ on fs
 
 on late-fs
     mount_all /vendor/etc/fstab.${ro.boot.hardware} --late
+
+on boot
+    mount configfs none /config
+    mkdir /config/usb_gadget/g1 0770
+    mkdir /config/usb_gadget/g1/strings/0x409 0770
+    write /config/usb_gadget/g1/bcdUSB 0x0200
+    write /config/usb_gadget/g1/os_desc/use 1
+    write /config/usb_gadget/g1/strings/0x409/serialnumber ${ro.serialno}
+    write /config/usb_gadget/g1/strings/0x409/manufacturer ${ro.product.manufacturer}
+    mkdir /config/usb_gadget/g1/functions/ffs.adb
+    mkdir /config/usb_gadget/g1/configs/b.1 0770
+    mkdir /config/usb_gadget/g1/configs/b.1/strings/0x409 0770
+    write /config/usb_gadget/g1/configs/b.1/MaxPower 900
+    write /config/usb_gadget/g1/os_desc/b_vendor_code 0x1
+    write /config/usb_gadget/g1/os_desc/qw_sign "MSFT100"
+    symlink /config/usb_gadget/g1/configs/b.1 /config/usb_gadget/g1/os_desc/b.1
+    mkdir /dev/usb-ffs 0775 shell system
+    mkdir /dev/usb-ffs/adb 0770 shell system
+    mount functionfs adb /dev/usb-ffs/adb uid=2000,gid=1000,rmode=0770,fmode=0660
+
+# WAR for stock kernel setting CONFIG_USB_DUMMY_HCD=y since FunctionFS won't mount with a dummy controller
+on property:sys.usb.controller=dummy_udc.0
+    setprop sys.usb.controller ${ro.boot.usbcontroller}
+    setprop sys.usb.configfs 1
+
+on property:sys.usb.config=adb && property:sys.usb.configfs=1
+    write /config/usb_gadget/g1/idVendor 0x18d1
+    write /config/usb_gadget/g1/idProduct 0x4ee7
```

Now time to get our proprietary blobs.

# Vendor Tree
LineageOS has some [excellent scripts](https://github.com/LineageOS/android_tools_extract-utils/) for extracting the proprietary binaries from a device and automatically generating the makefiles for the vendor tree, which I cloned into my AOSP source tree. 
We can also use [aospdtgen](https://github.com/sebaubuntu-python/aospdtgen) to automatically create `proprietary-files.txt`, the list of blobs that are on the device.
I cloned the stock dump from [tadiphone](https://dumps.tadiphone.dev/dumps/motorola/ibiza/-/tree/user-12-S1RFS32.27-25-1-bcca0-release-keys/) (I have each partition image already but they're not quite in the structure it expects since I mount the images into non-standard directories and things like that), and then ran `python -m aospdtgen -o /tmp/gen /tmp/tmp.OuELFvpyTG/ibiza` to create
the tree. I only need `proprietary-files.txt` and `extract-files.py` which we can copy into `device/motorola/ibiza`, but this can also be a good starting point for future device bringups if you're not interested in repeating a lot of the manual work done above for every single device. Then, I run `./extract-files.py /tmp/tmp.OuELFvpyTG/ibiza` to create the vendor tree at `vendor/motorola/ibiza`.
The `proprietary-files.txt` required a couple changes for duplicate files or files that were only in `vendor/lib64` but not `vendor/lib`, and some libraries were text files representing symlinks, so I had to remove those paths as well.

The old way of copying all these blobs into their respective partitions was to add them to `PRODUCT_COPY_FILES`, but in newer Android versions, copying ELF files is disallowed. We could get this back by setting `BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true`, but the better way to do it is to use `./setup-makefiles.py`, which will create `cc_prebuilt_library_shared` modules for each
proprietary blob in `vendor/motorola/ibiza/Android.bp`. This way we can add the blobs to `PRODUCT_PACKAGES` and shared library dependencies can be extracted automatically from the ELF metadata (which means you'll get build errors instead of runtime errors and don't need to manually check readelf for every library), which is super helpful).

When I tried to `m`, I got a lot of duplicate definition errors:
```
error: vendor/motorola/ibiza/Android.bp:41125:1: module "prebuilt_libmmosal" already defined
       vendor/motorola/ibiza/Android.bp:20147:1 <-- previous definition here
```

This was because my stock ROM had `libmmosal.so` in both the `vendor` and `system_ext` partitions, and the prebuilt modules both had the same name. The `extract-files.py` script can actually do much more than just copy files, but it can actually patch instructions, ELF dependencies, etc. For example, you could [add a suffix to each library](https://github.com/LineageOS/android_device_xiaomi_sdm845-common/blob/lineage-23.2/extract-files.py#L32),
but for now I'll just comment out most of the blobs listed, and add them in 1-by-1 as I need them. That way, I don't have to solve a bunch of dependency errors at once for blobs that may not even turn out to be required. Plus, a lot of them are also provided by the HALs we cloned early.

# Iterating
## OpenGL ES & EGL
We now get much further into the system startup - Zygote, the process from which all other processes are `fork()`ed for efficiency reasons is starting, as well as SurfaceFlinger, which is required for hardware acceleration and displaying the boot animation (this whole time we've just seen the Motorola boot logo).
```bash
10-22 03:12:46.430   756   756 F DEBUG   : pid: 718, tid: 718, name: main  >>> zygote64 <<<
10-22 03:12:46.430   756   756 F DEBUG   : uid: 0
10-22 03:12:46.430   756   756 F DEBUG   : signal 6 (SIGABRT), code -1 (SI_QUEUE), fault addr --------
10-22 03:12:46.430   756   756 F DEBUG   : Abort message: 'couldn't find an OpenGL ES implementation, make sure you set ro.hardware.egl or ro.board.platform'
10-22 03:12:46.212   718   718 F zygote64: runtime.cc:669]   native: #08 pc 0000000000023f60  /system/lib64/libEGL.so (android::Loader::open(android::egl_connection_t*)+1192)
10-22 03:12:46.212   718   718 F zygote64: runtime.cc:669]   native: #09 pc 000000000001b9b4  /system/lib64/libEGL.so (android::egl_init_drivers()+80)
10-22 03:12:46.212   718   718 F zygote64: runtime.cc:669]   native: #10 pc 000000000001bc98  /system/lib64/libEGL.so (eglGetDisplay+24)
10-22 03:12:46.212   718   718 F zygote64: runtime.cc:669]   native: #11 pc 000000000047ebf8  /system/lib64/libhwui.so (zygote_preload_graphics+84)
```

No GLES implemention? Then what's `libEGL.so` in system? This platform library is essentially just a wrapper that calls into the hardware-specific vendor implementations, such as `libEGL_adreno.so`.
The [AOSP docs for EGL](https://source.android.com/docs/core/graphics/implement-opengl-es#driver_emun) tells us that the implementation is found using `ro.hardware.egl`, so we'll need to set that to `adreno` and provide the prebuilt libraries mentioned as well.

We fix some runtime linker errors (this library is also declared in the display HAL):
```bash
10-23 06:37:16.505   682   682 D libEGL  : loaded /vendor/lib64/egl/libEGL_adreno.so
10-23 06:37:16.600   682   682 D libEGL  : loaded /vendor/lib64/egl/libGLESv1_CM_adreno.so
10-23 06:37:16.611   682   682 D libEGL  : loaded /vendor/lib64/egl/libGLESv2_adreno.so
10-23 06:37:17.454   760   760 F linker  : CANNOT LINK EXECUTABLE "/vendor/bin/hw/vendor.qti.hardware.display.composer-service": library "libdisplaydebug.so" not found: needed by main executable
```

and face some more seemingly cryptic errors:
```bash
10-23 06:50:29.345   769   769 I SurfaceFlinger: SurfaceFlinger main thread ready to run. Initializing graphics H/W...
10-23 06:50:29.345   769   769 D RenderEngine: Threaded RenderEngine with SkiaGL Backend
10-23 06:50:29.394   769   785 E libEGL  : eglInitializeImpl:280 error 3008 (EGL_BAD_DISPLAY)
10-23 06:50:29.394   769   785 F RenderEngine: failed to initialize EGL
10-23 06:50:29.394   769   785 F libc    : Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid 785 (surfaceflinger), pid 769 (surfaceflinger)
```

`eglInitializeImpl` is provided by `libEGL_adreno` which calls into the actual implementations like `libGLESv2_adreno.so`. Luckily, we know there's nothing wrong with these blobs since they were created for our stock Android version - we could have some patching work to do if we were porting a newer version of Android, so it must be something fairly obvious.

Reading the logs further, we see that the display composer HAL doesn't seem to be doing much, like it's just looping.
```bash
10-23 07:16:16.606   551   551 I SDM     : Creating Display HW Composer HAL
10-23 07:16:16.607   551   551 I SDM     : ProcessState initialization completed
10-23 07:16:16.607   551   551 I SDM     : Scheduler priority settings completed
10-23 07:16:16.607   551   551 I SDM     : Initializing QtiComposer
10-23 07:16:16.607   551   551 I SDM     : HWCSession::Init: Initializing HWCSession
10-23 07:16:16.607   551   551 I SDM     : HWCSession::Init: HWCUEvent initialization confirmed to be completed
10-23 07:16:16.607   551   551 I SDM     : HWCSession::Init: Initializing QService
10-23 07:16:16.981   551   568 W SDM     : HWCSession::UEventThread: UEvent dropped. No uevent listener.
10-23 07:16:17.077   551   568 W SDM     : HWCSession::UEventThread: UEvent dropped. No uevent listener.
```

If we `strace` it, we can indeed see it's trying to make Binder calls and waiting for `/dev/vndbinder`:
```bash
ibiza:/ # strace -s256 /vendor/bin/hw/vendor.qti.hardware.display.composer-service
writev(5, [{iov_base="l=\0\0\0\304\22", iov_len=7}, {iov_base="\0\304\22\232Q\205\1w[\235\1", iov_len=11}, {iov_base="\4", iov_len=1}, {iov_base="qdqservice\0", iov_len=11}, {iov_base="Creating defaultServiceManager\0", iov_len=31}], 5) = 61
getuid()                                = 0
ioctl(6, BINDER_WRITE_READ, 0x7fc6267408) = 0
getuid()                                = 0
writev(4, [{iov_base="\0\304\22\232Q\205\1\356\204F\2", iov_len=11}, {iov_base="\5", iov_len=1}, {iov_base="ProcessState\0", iov_len=13}, {iov_base="Not able to get context object on /dev/vndbinder.\0", iov_len=50}], 4) = 75
getuid()                                = 0
writev(5, [{iov_base="lR\0\0\0\304\22", iov_len=7}, {iov_base="\0\304\22\232Q\205\1\356\204F\2", iov_len=11}, {iov_base="\5", iov_len=1}, {iov_base="ProcessState\0", iov_len=13}, {iov_base="Not able to get context object on /dev/vndbinder.\0", iov_len=50}], 5) = 82
getuid()                                = 0
writev(4, [{iov_base="\0\304\22\232Q\205\1\7[W\2", iov_len=11}, {iov_base="\6", iov_len=1}, {iov_base="ServiceManager\0", iov_len=15}, {iov_base="Waiting 1s on context object on /dev/vndbinder.\0", iov_len=48}], 4) = 75
getuid()                                = 0
writev(5, [{iov_base="lR\0\0\0\304\22", iov_len=7}, {iov_base="\0\304\22\232Q\205\1\7[W\2", iov_len=11}, {iov_base="\6", iov_len=1}, {iov_base="ServiceManager\0", iov_len=15}, {iov_base="Waiting 1s on context object on /dev/vndbinder.\0", iov_len=48}], 5) = 82
```

This is because Android 8 split `/dev/binder` [into 3](https://source.android.com/docs/core/architecture/hidl/binder-ipc#vndbinder) depending on if it's an AIDL or HIDL service, and if it's a framework or vendor process.
We can add `PRODUCT_PACKAGES += vndservicemanager` to our device tree, fix some `dlopen` failed errors by adding more shared libraries, and adding `hardware/qcom/display` to the Soong namespaces `namespace_imports` in `extract-files.py` since the `setup-makefiles.py` script generates the file and would remove our changes.

Next, we get a null pointer dereference in our display composer HAL:
```bash
pid: 4606, tid: 4606, name: vendor.qti.hard  >>> /vendor/bin/hw/vendor.qti.hardware.display.composer-service <<<
uid: 1000
signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0
Cause: null pointer dereference

backtrace:
      #00 pc 000000000005f400  /vendor/bin/hw/vendor.qti.hardware.display.composer-service (sdm::HWCSession::CreatePrimaryDisplay()+288) (BuildId: 5e14d34edac8d57d0912384ed9b5fc8e)
      #01 pc 000000000005ec28  /vendor/bin/hw/vendor.qti.hardware.display.composer-service (sdm::HWCSession::Init()+1204) (BuildId: 5e14d34edac8d57d0912384ed9b5fc8e)
      #02 pc 0000000000023828  /vendor/bin/hw/vendor.qti.hardware.display.composer-service (vendor::qti::hardware::display::composer::V3_0::implementation::QtiComposer::initialize()+16) (BuildId: 5e14d34edac8d57d0912384ed9b5fc8e)
      #03 pc 000000000007429c  /vendor/bin/hw/vendor.qti.hardware.display.composer-service (main+272) (BuildId: 5e14d34edac8d57d0912384ed9b5fc8e)
      #04 pc 00000000000484b4  /apex/com.android.runtime/lib64/bionic/libc.so (__libc_init+96) (BuildId: e7ff69a47144efab6226bedea885d21a)
```

Now, we could try and debug this with LLDB, using `> prebuilts/gdb/linux-x86/bin/python2 /aosp/android-12-1-0/development/scripts/lldbclient.py -r /vendor/bin/hw/vendor.qti.hardware.display.composer-service`:
```cpp
* thread #1, name = 'vendor.qti.hard', stop reason = step over
    frame #0: 0x0000007ff335e504 libsdmcore.so`sdm::CompManager::Init(this=0xb400007ef03db658, hw_res_info=0xb400007ef03db438, extension_intf=0xb400007df03db670, buffer_allocator=0xb400007f003e0530, socket_handler=0xb400007f003e0610) at comp_manager.cpp:48:29
   45  	 DisplayError error = kErrorNone;
   46  	
   47  	 if (extension_intf) {
-> 48  	   error = extension_intf->CreateResourceExtn(hw_res_info, buffer_allocator, &resource_intf_);
   49  	   extension_intf->CreateDppsControlExtn(&dpps_ctrl_intf_, socket_handler);
   50  	 } else {
   51  	   error = ResourceDefault::CreateResourceDefault(hw_res_info, &resource_intf_);
(lldb) p error
(sdm::DisplayError) $6 = kErrorNotSupported
```
(it ends up calling `delete core_intf_` which causes the null dereference)

but luckily, in 99% of the cases, especially for the same Android version, it just comes down to more missing libraries.
```bash
10-23 08:06:38.905  5538  5538 W SDM     : ScalarConfig::Init: libqseed3.so not present, scalar will not be used
10-23 08:06:38.908  5538  5538 E SDM     : HWCSession::InitSupportedDisplaySlots: Failed to create CoreInterface
```

Adding that library worked, and then we get:
```bash
10-23 08:24:58.042   988   988 W SDM     : HDRIntfClient::Init: HDRIntfLib open failed
10-23 08:24:58.042   988   988 W SDM     : ToneMapConfigImpl::InitializeHDRIntf: HDRIntf Lib failed
10-23 08:24:58.042   988   988 E SDM     : ToneMapConfigImpl::RegisterDisplay: Failed to InitializeHDRIntf for display type = 0
10-23 08:24:58.042   988   988 I scudo   : Scudo ERROR: invalid chunk state when deallocating address 0x200007b4ea82820
```

I'm not sure why we're getting heap corruption, but `vendor/lib/libhdr_tm.so` sounds like a good match for `HDRIntf Lib`, and indeed, we now have the HAL registered when we check `lshal`:
```bash
X     ? android.hardware.graphics.mapper@4.0::I*/* (/vendor/lib64/hw/) (-qti-display) N/A        N/A
DM,FC Y vendor.qti.hardware.display.allocator@3.0::IQtiAllocator/default 0/3        549    448
DM,FC Y vendor.qti.hardware.display.composer@3.0::IQtiComposer/default   0/2        555    448
```

However, the `EGL_BAD_DISPLAY` error is still happening. Turns out we also need `vendor/lib/egl/eglSubDriverAndroid.so`.

Our driver is up now:
```bash
10-23 18:11:53.582   763   773 I AdrenoGLES-0: QUALCOMM build                   : cac6e6f805, I5187d04b75
10-23 18:11:53.582   763   773 I AdrenoGLES-0: Build Date                       : 11/22/21
10-23 18:11:53.582   763   773 I AdrenoGLES-0: OpenGL ES Shader Compiler Version: EV031.35.01.10
10-23 18:11:53.582   763   773 I AdrenoGLES-0: Local Branch                     :
10-23 18:11:53.582   763   773 I AdrenoGLES-0: Remote Branch                    :
10-23 18:11:53.582   763   773 I AdrenoGLES-0: Remote Branch                    :
10-23 18:11:53.582   763   773 I AdrenoGLES-0: Reconstruct Branch               :
10-23 18:11:53.582   763   773 I AdrenoGLES-0: Build Config                     : S P 10.0.7 AArch64
10-23 18:11:53.582   763   773 I AdrenoGLES-0: Driver Path                      : /vendor/lib64/egl/libGLESv2_adreno.so
```

but we get a new error:
```bash
Abort message: 'no suitable EGLConfig found, giving up'
10-23 08:43:43.571   806   810 E ion     : open /dev/ion failed: Permission denied
10-23 08:43:43.571   806   810 E qdgralloc: Init: Failed to open ion device - Permission denied
10-23 08:43:43.572   806   810 E Adreno-GSL: <ioctl_kgsl_driver_entry:996>: open(/dev/kgsl-3d0) failed: errno 13. Permission denied
```

Device node permissions are set in `vendor/ueventd.rc`, so we can copy it from there.

And that gives us:
```bash
10-23 18:11:53.596   763   773 E Adreno-GSL: <ioctl_kgsl_driver_entry:996>: open(/dev/kgsl-3d0) failed: errno 2. No such file or directory
10-23 18:11:53.596   763   773 W libEGL  : eglInitialize(0xb4000072fdae8ed0) failed (EGL_BAD_ALLOC)
10-23 18:11:53.596   763   773 W RenderEngine: no suitable EGLConfig found, trying a simpler query
10-23 18:11:53.597   763   773 F RenderEngine: no suitable EGLConfig found, giving up
```

You might think it's a weird error, since the 'file' exists:
```bash
ibiza:/ # ls -la /dev/kgsl-3d0
crw-rw-rw- 1 system system 510,   0 1970-10-23 18:11 /dev/kgsl-3d0
```

but in fact, if we `cat` it, we see:
```bash
ibiza:/ # cat /dev/kgsl-3d0
cat: /dev/kgsl-3d0: No such file or directory
```

A bit contradictory, right? That's because this is a special kernel device node, not a real file.

Luckily, the error message is clear in that it's trying to load firmware:
```bash
10-23 18:11:53.595     0     0 I ueventd : firmware: loading 'a630_sqe.fw' for '/devices/platform/soc/5900000.qcom,kgsl-3d0/firmware/a630_sqe.fw'
10-23 18:11:53.596     0     0 E ueventd : firmware: could not find firmware for a630_sqe.fw
10-23 18:11:53.596     0     0 E ueventd : firmware: attempted /etc/firmware/a630_sqe.fw, open failed: No such file or directory
10-23 18:11:53.596     0     0 E ueventd : firmware: attempted /odm/firmware/a630_sqe.fw, open failed: No such file or directory
10-23 18:11:53.596     0     0 E ueventd : firmware: attempted /vendor/firmware/a630_sqe.fw, open failed: No such file or directory
10-23 18:11:53.596     0     0 E ueventd : firmware: attempted /firmware/image/a630_sqe.fw, open failed: No such file or directory
10-23 18:11:53.596     0     0 E ueventd : firmware: attempted /vendor/firmware_mnt/image/a630_sqe.fw, open failed: No such file or directory
10-23 18:11:53.596     0     0 I ueventd : loading /devices/platform/soc/5900000.qcom,kgsl-3d0/firmware/a630_sqe.fw took 0ms
10-23 18:11:53.596     0     0 E kgsl-3d0: request_firmware(a630_sqe.fw) failed: -2
```

If we add it and `strace system/bin/surfaceflinger` again, we see:
```bash
writev(4, [{iov_base="\0\326\f\34\356\205\1\234\356\26\t", iov_len=11}, {iov_base="\4", iov_len=1}, {iov_base="HidlServiceManagement\0", iov_len=22}, {iov_base="getService: Trying again for android.hardware.graphics.allocator@4.0::IAllocator/default...\0", iov_len=92}], 4) = 126
getuid()                                = 0
writev(5, [{iov_base="l\205\0\0\0\326\f", iov_len=7}, {iov_base="\0\326\f\34\356\205\1\234\356\26\t", iov_len=11}, {iov_base="\4", iov_len=1}, {iov_base="HidlServiceManagement\0", iov_len=22}, {iov_base="getService: Trying again for android.hardware.graphics.allocator@4.0::IAllocator/default...\0", iov_len=92}], 5) = 133
```

If we check out the service, we see that `TARGET_USES_GRALLOC4` must be defined to register the 4.0 service:
```cpp,name=hardware/qcom/display/gralloc/service.cpp
#ifdef TARGET_USES_GRALLOC4
  android::sp<IQtiAllocator4> service4 =
      new vendor::qti::hardware::display::allocator::V4_0::implementation::QtiAllocator();
  if (service4->registerAsService() != android::OK) {
    ALOGE("Cannot register QTI Allocator 4 service");
    return -EINVAL;
  }
  ALOGI("Initialized qti-allocator 4");
#endif
```

so we define those SOONG_CONFIG variables and...

## Boot Animation!
{{ figure(src="./bootanimation.jpeg", width=300, height=50, caption="Boot Animation") }}
Our first visual sign of progress that something's happening. We have hardware acceleration working, and can now continue with the rest of the services started by `init`.
```bash
10-23 21:12:18.042   544   544 I SurfaceFlinger: Enter boot animation
10-23 21:12:18.130   671   671 I SystemServer: Entered the Android system server!
```

## More HALs
We can see the HALs it's trying to start, and add them in.
```bash
10-23 21:12:24.236     0     0 E init    : Control message: Could not find 'android.hardware.audio@6.0::IDevicesFactory/default' for ctl.interface_start from pid: 446 (/system/bin/hwservicemanager)
10-23 21:12:25.799     0     0 E init    : Control message: Could not find 'android.hardware.memtrack@1.0::IMemtrack/default' for ctl.interface_start from pid: 446 (/system/bin/hwservicemanager)
10-23 21:23:14.059     0     0 E init    : Control message: Could not find 'android.hardware.audio.effect@6.0::IEffectsFactory/default' for ctl.interface_start from pid: 451 (/system/bin/hwservicemanager)
10-23 21:23:14.078   767   767 F DEBUG   : pid: 760, tid: 760, name: audio.service  >>> /vendor/bin/hw/android.hardware.audio.service <<<
10-23 21:23:14.078   767   767 F DEBUG   : Abort message: 'Could not register Audio Effect API'
```

```diff
diff --git a/device-ibiza.mk b/device-ibiza.mk
index 54cc63b..092f5cc 100644
--- a/device-ibiza.mk
+++ b/device-ibiza.mk
@@ -94,5 +94,13 @@ PRODUCT_PACKAGES += \
 PRODUCT_PACKAGES += \
         libdisplaydebug

+PRODUCT_PACKAGES += \
+    android.hardware.memtrack@1.0-impl \
+    android.hardware.memtrack@1.0-service \
+    lights.$(TARGET_BOARD_PLATFORM) \
+    memtrack.default \
+    android.hardware.audio.service \
+    android.hardware.audio@6.0-impl \
+    android.hardware.audio.effect@6.0-util \
+    android.hardware.audio.common-util \
+    android.hardware.soundtrigger@2.1.vendor \
+    android.hardware.soundtrigger@2.2.vendor \
+    android.hardware.soundtrigger@2.3.vendor \
+    android.hardware.soundtrigger@2.3-impl \
+    android.hardware.bluetooth@1.0.vendor \
+    android.hardware.bluetooth.audio@2.0-impl
+
 # Inherit from the proprietary files makefile.
 $(call inherit-product, vendor/motorola/ibiza/ibiza-vendor.mk)
```

These new HALs are up:
```bash
> adb wait-for-device shell "lshal"
| All HIDL binderized services (registered with hwservicemanager)
VINTF R Interface                                                        Thread Use Server Clients
DM,FC Y android.hardware.audio.effect@6.0::IEffectsFactory/default       0/4        528    543 451
DM,FC Y android.hardware.audio@6.0::IDevicesFactory/default              0/4        528    543 451
DM,FC Y android.hardware.memtrack@1.0::IMemtrack/default                 0/1        532    451
DM,FC Y android.hardware.soundtrigger@2.0::ISoundTriggerHw/default       0/4        528    451
DM,FC Y android.hardware.soundtrigger@2.1::ISoundTriggerHw/default       0/4        528    451
DM,FC Y android.hardware.soundtrigger@2.2::ISoundTriggerHw/default       0/4        528    451
DM,FC Y android.hardware.soundtrigger@2.3::ISoundTriggerHw/default       0/4        528    451

VINTF R Interface                                                  Thread Use Server Clients
FC    ? android.hardware.audio.effect@6.0::IEffectsFactory/default N/A        528    528
FC    ? android.hardware.audio@6.0::IDevicesFactory/default        N/A        528    528
FC    ? android.hardware.memtrack@1.0::IMemtrack/default           N/A        532    532
FC    ? android.hardware.soundtrigger@2.3::ISoundTriggerHw/default N/A        528    528

VINTF R Interface                                                                     Thread Use Server Clients
X     ? android.hardware.audio.effect@6.0::I*/* (/vendor/lib/hw/)                     N/A        N/A    528
X     ? android.hardware.audio.effect@6.0::I*/* (/vendor/lib64/hw/)                   N/A        N/A
X     ? android.hardware.audio@6.0::I*/* (/vendor/lib/hw/)                            N/A        N/A    528
X     ? android.hardware.audio@6.0::I*/* (/vendor/lib64/hw/)                          N/A        N/A
X     ? android.hardware.health@2.0::I*/* (/vendor/lib64/hw/) (-2.1-qti)              N/A        N/A    530
X     ? android.hardware.memtrack@1.0::I*/* (/vendor/lib/hw/)                         N/A        N/A
X     ? android.hardware.memtrack@1.0::I*/* (/vendor/lib64/hw/)                       N/A        N/A    532
X     ? android.hardware.soundtrigger@2.3::I*/* (/vendor/lib/hw/)                     N/A        N/A    528
X     ? android.hardware.soundtrigger@2.3::I*/* (/vendor/lib64/hw/)                   N/A        N/A
```

## Keymaster & Gatekeeper
We skipped out on userdata encryption, but looks like we won't get away with skipping Gatekeeper & Keymaster after all..

{% detail(title="IKeystore Errors", default_open=false) %}
```Java
06-24 01:01:51.402 16176 16176 V SystemUIService: SystemUIApplication constructed.
06-24 01:02:03.376 16682 16702 I WindowManager: ******* TELLING SURFACE FLINGER WE ARE BOOTED!
06-24 01:02:03.458 16682 16702 I ActivityManager: User 0 state changed from BOOTING to RUNNING_LOCKED
06-24 01:02:03.457     0     0 I init    : processing action (sys.boot_completed=1) from (/system/etc/init/hw/init.rc:1145)
06-24 01:02:03.866 16682 16699 I ActivityManager: User 0 state changed from RUNNING_LOCKED to RUNNING_UNLOCKING
06-24 01:02:03.870   453   453 I vold    : onUserStarted: 0
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: Can not connect to keystore
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: java.lang.NullPointerException: Attempt to invoke interface method 'int android.security.maintenance.IKeystoreMaintenance.getState(int)' on a null object reference
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at android.security.AndroidKeyStoreMaintenance.getState(AndroidKeyStoreMaintenance.java:133)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at android.security.KeyStore.state(KeyStore.java:59)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at com.android.server.locksettings.LockSettingsService.ensureProfileKeystoreUnlocked(LockSettingsService.java:742)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at com.android.server.locksettings.LockSettingsService.access$500(LockSettingsService.java:188)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at com.android.server.locksettings.LockSettingsService$1.run(LockSettingsService.java:760)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at android.os.Handler.handleCallback(Handler.java:938)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at android.os.Handler.dispatchMessage(Handler.java:99)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at android.os.Looper.loop(Looper.java:288)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at android.os.HandlerThread.run(HandlerThread.java:67)
06-24 01:02:03.873 16682 16764 E AndroidKeyStoreMaintenance: 	at com.android.server.ServiceThread.run(ServiceThread.java:44)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: *** FATAL EXCEPTION IN SYSTEM PROCESS: LockSettingsService
06-24 01:02:03.874 16682 16764 E AndroidRuntime: java.lang.AssertionError: 4
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at android.security.KeyStore.state(KeyStore.java:68)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService.ensureProfileKeystoreUnlocked(LockSettingsService.java:742)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService.access$500(LockSettingsService.java:188)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService$1.run(LockSettingsService.java:760)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at android.os.Handler.handleCallback(Handler.java:938)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:99)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at android.os.HandlerThread.run(HandlerThread.java:67)
06-24 01:02:03.874 16682 16764 E AndroidRuntime: 	at com.android.server.ServiceThread.run(ServiceThread.java:44)
06-24 01:02:04.012 16622 16622 I Zygote  : Process 16682 exited due to signal 9 (Killed)
06-24 01:02:04.012 16622 16622 E Zygote  : Exit zygote because system server (pid 16682) has terminated
```
{% end %}

{% detail(title="Even more crashes", default_open=false) %}
```Bash
--------- beginning of crash
06-24 00:56:57.294 28321 28321 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:56:57.294 28321 28321 E AndroidRuntime: Process: com.android.bluetooth, PID: 28321
06-24 00:56:57.294 28321 28321 E AndroidRuntime: java.lang.RuntimeException: Unable to create service com.android.bluetooth.btservice.AdapterService: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4567)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.app.ActivityThread.access$1700(ActivityThread.java:256)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.app.ActivityThread$H.handleMessage(ActivityThread.java:2110)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:106)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.app.ActivityThread.main(ActivityThread.java:7870)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at java.lang.reflect.Method.invoke(Native Method)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:548)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:1003)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: Caused by: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.security.KeyStore2.getService(KeyStore2.java:144)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.security.KeyStore2.handleRemoteExceptionWithRetry(KeyStore2.java:105)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.security.KeyStore2.getKeyEntry(KeyStore2.java:252)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.getKeyMetadata(AndroidKeyStoreSpi.java:156)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.engineContainsAlias(AndroidKeyStoreSpi.java:1007)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at java.security.KeyStore.containsAlias(KeyStore.java:1293)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at com.android.bluetooth.btservice.bluetoothkeystore.BluetoothKeystoreService.start(BluetoothKeystoreService.java:156)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at com.android.bluetooth.btservice.AdapterService.onCreate(AdapterService.java:512)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4554)
06-24 00:56:57.294 28321 28321 E AndroidRuntime: 	... 9 more
06-24 00:56:58.573 28629 28629 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:56:58.573 28629 28629 E AndroidRuntime: Process: com.android.bluetooth, PID: 28629
06-24 00:56:58.573 28629 28629 E AndroidRuntime: java.lang.RuntimeException: Unable to create service com.android.bluetooth.btservice.AdapterService: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4567)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.app.ActivityThread.access$1700(ActivityThread.java:256)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.app.ActivityThread$H.handleMessage(ActivityThread.java:2110)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:106)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.app.ActivityThread.main(ActivityThread.java:7870)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at java.lang.reflect.Method.invoke(Native Method)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:548)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:1003)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: Caused by: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.security.KeyStore2.getService(KeyStore2.java:144)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.security.KeyStore2.handleRemoteExceptionWithRetry(KeyStore2.java:105)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.security.KeyStore2.getKeyEntry(KeyStore2.java:252)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.getKeyMetadata(AndroidKeyStoreSpi.java:156)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.engineContainsAlias(AndroidKeyStoreSpi.java:1007)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at java.security.KeyStore.containsAlias(KeyStore.java:1293)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at com.android.bluetooth.btservice.bluetoothkeystore.BluetoothKeystoreService.start(BluetoothKeystoreService.java:156)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at com.android.bluetooth.btservice.AdapterService.onCreate(AdapterService.java:512)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4554)
06-24 00:56:58.573 28629 28629 E AndroidRuntime: 	... 9 more
06-24 00:56:59.725 28149 28233 E AndroidRuntime: *** FATAL EXCEPTION IN SYSTEM PROCESS: LockSettingsService
06-24 00:56:59.725 28149 28233 E AndroidRuntime: java.lang.AssertionError: 4
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at android.security.KeyStore.state(KeyStore.java:68)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService.ensureProfileKeystoreUnlocked(LockSettingsService.java:742)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService.access$500(LockSettingsService.java:188)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService$1.run(LockSettingsService.java:760)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at android.os.Handler.handleCallback(Handler.java:938)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:99)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at android.os.HandlerThread.run(HandlerThread.java:67)
06-24 00:56:59.725 28149 28233 E AndroidRuntime: 	at com.android.server.ServiceThread.run(ServiceThread.java:44)
06-24 00:56:59.851 28334 28334 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:56:59.851 28334 28334 E AndroidRuntime: Process: com.android.systemui, PID: 28334
06-24 00:56:59.851 28334 28334 E AndroidRuntime: DeadSystemException: The system died; earlier logs will point to the root cause
06-24 00:57:10.015 29001 29001 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:57:10.015 29001 29001 E AndroidRuntime: Process: com.android.bluetooth, PID: 29001
06-24 00:57:10.015 29001 29001 E AndroidRuntime: java.lang.RuntimeException: Unable to create service com.android.bluetooth.btservice.AdapterService: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4567)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.app.ActivityThread.access$1700(ActivityThread.java:256)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.app.ActivityThread$H.handleMessage(ActivityThread.java:2110)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:106)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.app.ActivityThread.main(ActivityThread.java:7870)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at java.lang.reflect.Method.invoke(Native Method)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:548)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:1003)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: Caused by: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.security.KeyStore2.getService(KeyStore2.java:144)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.security.KeyStore2.handleRemoteExceptionWithRetry(KeyStore2.java:105)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.security.KeyStore2.getKeyEntry(KeyStore2.java:252)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.getKeyMetadata(AndroidKeyStoreSpi.java:156)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.engineContainsAlias(AndroidKeyStoreSpi.java:1007)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at java.security.KeyStore.containsAlias(KeyStore.java:1293)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at com.android.bluetooth.btservice.bluetoothkeystore.BluetoothKeystoreService.start(BluetoothKeystoreService.java:156)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at com.android.bluetooth.btservice.AdapterService.onCreate(AdapterService.java:512)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4554)
06-24 00:57:10.015 29001 29001 E AndroidRuntime: 	... 9 more
06-24 00:57:11.178 29330 29330 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:57:11.178 29330 29330 E AndroidRuntime: Process: com.android.bluetooth, PID: 29330
06-24 00:57:11.178 29330 29330 E AndroidRuntime: java.lang.RuntimeException: Unable to create service com.android.bluetooth.btservice.AdapterService: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4567)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.app.ActivityThread.access$1700(ActivityThread.java:256)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.app.ActivityThread$H.handleMessage(ActivityThread.java:2110)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:106)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.app.ActivityThread.main(ActivityThread.java:7870)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at java.lang.reflect.Method.invoke(Native Method)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:548)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:1003)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: Caused by: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.security.KeyStore2.getService(KeyStore2.java:144)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.security.KeyStore2.handleRemoteExceptionWithRetry(KeyStore2.java:105)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.security.KeyStore2.getKeyEntry(KeyStore2.java:252)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.getKeyMetadata(AndroidKeyStoreSpi.java:156)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.engineContainsAlias(AndroidKeyStoreSpi.java:1007)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at java.security.KeyStore.containsAlias(KeyStore.java:1293)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at com.android.bluetooth.btservice.bluetoothkeystore.BluetoothKeystoreService.start(BluetoothKeystoreService.java:156)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at com.android.bluetooth.btservice.AdapterService.onCreate(AdapterService.java:512)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4554)
06-24 00:57:11.178 29330 29330 E AndroidRuntime: 	... 9 more
06-24 00:57:12.497 28819 28922 E AndroidRuntime: *** FATAL EXCEPTION IN SYSTEM PROCESS: LockSettingsService
06-24 00:57:12.497 28819 28922 E AndroidRuntime: java.lang.AssertionError: 4
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at android.security.KeyStore.state(KeyStore.java:68)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService.ensureProfileKeystoreUnlocked(LockSettingsService.java:742)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService.access$500(LockSettingsService.java:188)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService$1.run(LockSettingsService.java:760)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at android.os.Handler.handleCallback(Handler.java:938)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:99)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at android.os.HandlerThread.run(HandlerThread.java:67)
06-24 00:57:12.497 28819 28922 E AndroidRuntime: 	at com.android.server.ServiceThread.run(ServiceThread.java:44)
06-24 00:57:12.709 29002 29278 E AndroidRuntime: FATAL EXCEPTION: AsyncTask #1
06-24 00:57:12.709 29002 29278 E AndroidRuntime: Process: com.android.systemui, PID: 29002
06-24 00:57:12.709 29002 29278 E AndroidRuntime: DeadSystemException: The system died; earlier logs will point to the root cause
06-24 00:57:20.217 29687 29687 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:57:20.217 29687 29687 E AndroidRuntime: Process: com.android.bluetooth, PID: 29687
06-24 00:57:20.217 29687 29687 E AndroidRuntime: java.lang.RuntimeException: Unable to create service com.android.bluetooth.btservice.AdapterService: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4567)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.app.ActivityThread.access$1700(ActivityThread.java:256)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.app.ActivityThread$H.handleMessage(ActivityThread.java:2110)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:106)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.app.ActivityThread.main(ActivityThread.java:7870)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at java.lang.reflect.Method.invoke(Native Method)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:548)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:1003)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: Caused by: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.security.KeyStore2.getService(KeyStore2.java:144)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.security.KeyStore2.handleRemoteExceptionWithRetry(KeyStore2.java:105)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.security.KeyStore2.getKeyEntry(KeyStore2.java:252)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.getKeyMetadata(AndroidKeyStoreSpi.java:156)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.engineContainsAlias(AndroidKeyStoreSpi.java:1007)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at java.security.KeyStore.containsAlias(KeyStore.java:1293)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at com.android.bluetooth.btservice.bluetoothkeystore.BluetoothKeystoreService.start(BluetoothKeystoreService.java:156)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at com.android.bluetooth.btservice.AdapterService.onCreate(AdapterService.java:512)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4554)
06-24 00:57:20.217 29687 29687 E AndroidRuntime: 	... 9 more
06-24 00:57:21.446 30012 30012 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:57:21.446 30012 30012 E AndroidRuntime: Process: com.android.bluetooth, PID: 30012
06-24 00:57:21.446 30012 30012 E AndroidRuntime: java.lang.RuntimeException: Unable to create service com.android.bluetooth.btservice.AdapterService: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4567)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.app.ActivityThread.access$1700(ActivityThread.java:256)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.app.ActivityThread$H.handleMessage(ActivityThread.java:2110)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:106)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.app.ActivityThread.main(ActivityThread.java:7870)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at java.lang.reflect.Method.invoke(Native Method)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:548)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:1003)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: Caused by: java.lang.NullPointerException: Attempt to invoke interface method 'android.os.IBinder android.system.keystore2.IKeystoreService.asBinder()' on a null object reference
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.security.KeyStore2.getService(KeyStore2.java:144)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.security.KeyStore2.handleRemoteExceptionWithRetry(KeyStore2.java:105)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.security.KeyStore2.getKeyEntry(KeyStore2.java:252)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.getKeyMetadata(AndroidKeyStoreSpi.java:156)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.security.keystore2.AndroidKeyStoreSpi.engineContainsAlias(AndroidKeyStoreSpi.java:1007)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at java.security.KeyStore.containsAlias(KeyStore.java:1293)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at com.android.bluetooth.btservice.bluetoothkeystore.BluetoothKeystoreService.start(BluetoothKeystoreService.java:156)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at com.android.bluetooth.btservice.AdapterService.onCreate(AdapterService.java:512)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	at android.app.ActivityThread.handleCreateService(ActivityThread.java:4554)
06-24 00:57:21.446 30012 30012 E AndroidRuntime: 	... 9 more
06-24 00:57:22.833 29514 29596 E AndroidRuntime: *** FATAL EXCEPTION IN SYSTEM PROCESS: LockSettingsService
06-24 00:57:22.833 29514 29596 E AndroidRuntime: java.lang.AssertionError: 4
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at android.security.KeyStore.state(KeyStore.java:68)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService.ensureProfileKeystoreUnlocked(LockSettingsService.java:742)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService.access$500(LockSettingsService.java:188)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at com.android.server.locksettings.LockSettingsService$1.run(LockSettingsService.java:760)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at android.os.Handler.handleCallback(Handler.java:938)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at android.os.Handler.dispatchMessage(Handler.java:99)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at android.os.Looper.loopOnce(Looper.java:201)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at android.os.Looper.loop(Looper.java:288)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at android.os.HandlerThread.run(HandlerThread.java:67)
06-24 00:57:22.833 29514 29596 E AndroidRuntime: 	at com.android.server.ServiceThread.run(ServiceThread.java:44)
06-24 00:57:22.933 30126 30126 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:57:22.933 30126 30126 E AndroidRuntime: PID: 30126
06-24 00:57:22.933 30126 30126 E AndroidRuntime: DeadSystemException: The system died; earlier logs will point to the root cause
06-24 00:57:23.041 29868 29868 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:57:23.041 29868 29868 E AndroidRuntime: Process: com.android.settings, PID: 29868
06-24 00:57:23.041 29868 29868 E AndroidRuntime: DeadSystemException: The system died; earlier logs will point to the root cause
06-24 00:57:23.061 29976 29976 E AndroidRuntime: FATAL EXCEPTION: main
06-24 00:57:23.061 29976 29976 E AndroidRuntime: Process: com.android.launcher3, PID: 29976
06-24 00:57:23.061 29976 29976 E AndroidRuntime: DeadSystemException: The system died; earlier logs will point to the root cause
06-24 00:57:30.617 30385 30385 E AndroidRuntime: FATAL EXCEPTION: main
```
{% end %}

If we check out what the AOSP docs have to say:
> LockSettingsService The Android system component responsible for user authentication, both password and fingerprint. It's not part of Keystore, but is relevant because Keystore supports the concept of authentication bound keys: keys that can be used only if the user has authenticated. LockSettingsService interacts with the Gatekeeper TA and Fingerprint TA to obtain authentication tokens, which it provides to the keystore daemon, and which are consumed by the KeyMint TA.

we see that LockSettingsService -> Keystore -> Keymaster & Gatekeeper. We add those HALs in as blobs in our vendor tree:
{% detail(title="All required blobs", default_open=false) %}
```diff
diff --git a/proprietary-files.txt b/proprietary-files.txt
index d013000..a15c6cc 100644
--- a/proprietary-files.txt
+++ b/proprietary-files.txt
@@ -688,7 +688,7 @@
+vendor/lib/libdiag.so
@@ -715,7 +715,7 @@
+vendor/lib64/libdiag.so
@@ -1061,7 +1061,7 @@ vendor/firmware/a660_zap.mdt
+vendor/lib/libqcbor.so
@@ -1070,7 +1070,7 @@ vendor/lib/libqrtr.so
+vendor/lib64/libqcbor.so
@@ -1078,12 +1078,12 @@ vendor/lib64/libqrtr.so
+vendor/bin/qseecomd
+vendor/etc/init/qseecomd.rc
+vendor/lib/libQSEEComAPI.so
+vendor/lib/libdrmfs.so
+vendor/lib64/libQSEEComAPI.so
+vendor/lib64/libdrmfs.so
@@ -1141,8 +1141,10 @@ vendor/lib64/libqrtr.so
 #vendor/lib64/vendor.qti.hardware.fm@1.0.so
+vendor/bin/hw/android.hardware.gatekeeper@1.0-service-qti
+vendor/lib/hw/android.hardware.gatekeeper@1.0-impl-qti.so
+vendor/lib64/hw/android.hardware.gatekeeper@1.0-impl-qti.so
+vendor/etc/init/android.hardware.gatekeeper@1.0-service-qti.rc
@@ -1272,14 +1274,14 @@ vendor/lib64/libqrtr.so
+vendor/bin/hw/android.hardware.keymaster@4.1-service-qti
+vendor/etc/init/android.hardware.keymaster@4.1-service-qti.rc
+vendor/lib/libkeymasterdeviceutils.so
+vendor/lib/libkeymasterutils.so
+vendor/lib/libqtikeymaster4.so
+vendor/lib64/libkeymasterdeviceutils.so
+vendor/lib64/libkeymasterutils.so
+vendor/lib64/libqtikeymaster4.so
@@ -2113,8 +2115,8 @@ vendor/lib64/libqrtr.so
+vendor/lib/libtime_genoff.so
+vendor/lib64/libtime_genoff.so
@@ -2632,7 +2634,7 @@ vendor/lib64/libqrtr.so
+vendor/lib/libdrmtime.so
@@ -2680,7 +2682,7 @@ vendor/lib/libhdr_tm.so
+vendor/lib/libops.so
@@ -2702,7 +2704,7 @@ vendor/lib/libhdr_tm.so
+vendor/lib/libqisl.so
@@ -2724,7 +2726,7 @@ vendor/lib/libqseed3.so
+vendor/lib/librpmb.so
@@ -2740,7 +2742,7 @@ vendor/lib/libqseed3.so
+vendor/lib/libssd.so
@@ -2826,7 +2828,7 @@ vendor/lib/libqseed3.so
+vendor/lib64/libdrmtime.so
@@ -2879,7 +2881,7 @@ vendor/lib64/libhdr_tm.so
+vendor/lib64/libops.so
@@ -2902,7 +2904,7 @@ vendor/lib64/libhdr_tm.so
+vendor/lib64/libqisl.so
@@ -2926,7 +2928,7 @@ vendor/lib64/libqseed3.so
+vendor/lib64/librpmb.so
@@ -2941,7 +2943,7 @@ vendor/lib64/libqseed3.so
+vendor/lib64/libssd.so
```
{% end %}

# AOSP boots!
`com.android.bluetooth` is still crashing, but this finally gets us to the lockscreen!
{{ figure(src="./lockscreen.jpeg", width=300, height=50, caption="Lock screen") }}

# Fixing Userspace
We've gotten the system to boot, but it's far from useable. The volume buttons don't work, the brightness slider doesn't work, there are no navigation buttons, the Settings app crashes - we've got a lot
of work to do.

## Fixing touchscreen
We've run into this before when doing TWRP - we need the kernel module and firmware for our Novatek touchscreen:
```diff
diff --git a/BoardConfig.mk b/BoardConfig.mk
index bcb134d..c813623 100644
--- a/BoardConfig.mk
+++ b/BoardConfig.mk
@@ -103,3 +103,8 @@ BOARD_ROOT_EXTRA_FOLDERS := metadata

 # Display / EGL
 TARGET_USES_GRALLOC4 := true
+
+# LKM
+vendor_lkm_dir := $(LOCAL_PATH)/lkm-5.4
+BOARD_VENDOR_KERNEL_MODULES := \
+  $(vendor_lkm_dir)/nova_0flash_mmi.ko
diff --git a/init/init.hardware.rc b/init/init.hardware.rc
index e36d697..eff2cdc 100644
--- a/init/init.hardware.rc
+++ b/init/init.hardware.rc
@@ -6,6 +6,8 @@ on early-init
     loglevel 6
     setprop sys.init_log_level 6
     write /proc/sys/kernel/printk 7
+    exec u:r:vendor_modprobe:s0 -- /vendor/bin/modprobe -a -d \
+        /vendor/lib/modules nova_0flash_mmi

 on init
     wait /dev/block/platform/soc/${ro.boot.bootdevice}
diff --git a/lkm-5.4/nova_0flash_mmi.ko b/lkm-5.4/nova_0flash_mmi.ko
new file mode 100644
index 0000000..4e2117f
Binary files /dev/null and b/lkm-5.4/nova_0flash_mmi.ko differ
diff --git a/proprietary-files.txt b/proprietary-files.txt
index a15c6cc..b2d3dcd 100644
--- a/proprietary-files.txt
+++ b/proprietary-files.txt
@@ -2503,8 +2503,8 @@ vendor/lib64/libtime_genoff.so
 #vendor/firmware/ICNL9911.bin
 #vendor/firmware/NT36xxx_MP_Setting_Criteria_6033.csv
 #vendor/firmware/aw882xx_spk_reg.bin
-#vendor/firmware/novatek_ts_fw.bin
-#vendor/firmware/novatek_ts_mp.bin
+vendor/firmware/novatek_ts_fw.bin
+vendor/firmware/novatek_ts_mp.bin
 #vendor/firmware/vpu20_1v.b01
 #vendor/firmware/vpu20_1v.b02
 #vendor/firmware/vpu20_1v.b03
```

## Fixing Settings crash
{% detail(title="No service published for: wifi", default_open=false) %}
```Java
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry: No service published for: wifi
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry: android.os.ServiceManager$ServiceNotFoundException: No service published for: wifi
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.os.ServiceManager.getServiceOrThrow(ServiceManager.java:153)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.SystemServiceRegistry$134.createService(SystemServiceRegistry.java:1749)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.SystemServiceRegistry$CachedServiceFetcher.getService(SystemServiceRegistry.java:1848)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.SystemServiceRegistry.getSystemService(SystemServiceRegistry.java:1525)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.ContextImpl.getSystemService(ContextImpl.java:2081)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.view.ContextThemeWrapper.getSystemService(ContextThemeWrapper.java:188)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.Activity.getSystemService(Activity.java:6881)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at com.android.settings.deviceinfo.DeviceNamePreferenceController.<init>(DeviceNamePreferenceController.java:61)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at com.android.settings.deviceinfo.aboutphone.TopLevelAboutDevicePreferenceController.getSummary(TopLevelAboutDevicePreferenceController.java:37)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at com.android.settingslib.core.AbstractPreferenceController.refreshSummary(AbstractPreferenceController.java:59)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at com.android.settingslib.core.AbstractPreferenceController.updateState(AbstractPreferenceController.java:49)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at com.android.settings.dashboard.DashboardFragment.updatePreferenceStates(DashboardFragment.java:383)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at com.android.settings.dashboard.DashboardFragment.onResume(DashboardFragment.java:219)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.Fragment.performResume(Fragment.java:3029)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentStateManager.resume(FragmentStateManager.java:583)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentStateManager.moveToExpectedState(FragmentStateManager.java:282)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentStore.moveToExpectedState(FragmentStore.java:112)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentManager.moveToState(FragmentManager.java:1667)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentManager.dispatchStateChange(FragmentManager.java:3234)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentManager.dispatchResume(FragmentManager.java:3192)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentController.dispatchResume(FragmentController.java:273)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentActivity.onResumeFragments(FragmentActivity.java:434)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at androidx.fragment.app.FragmentActivity.onPostResume(FragmentActivity.java:423)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.Activity.performResume(Activity.java:8219)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.ActivityThread.performResumeActivity(ActivityThread.java:4814)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.ActivityThread.handleResumeActivity(ActivityThread.java:4857)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.servertransaction.ResumeActivityItem.execute(ResumeActivityItem.java:54)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.servertransaction.ActivityTransactionItem.execute(ActivityTransactionItem.java:45)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.servertransaction.TransactionExecutor.executeLifecycleState(TransactionExecutor.java:176)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.servertransaction.TransactionExecutor.execute(TransactionExecutor.java:97)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.ActivityThread$H.handleMessage(ActivityThread.java:2253)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.os.Handler.dispatchMessage(Handler.java:106)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.os.Looper.loopOnce(Looper.java:201)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.os.Looper.loop(Looper.java:288)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at android.app.ActivityThread.main(ActivityThread.java:7870)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at java.lang.reflect.Method.invoke(Native Method)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at com.android.internal.os.RuntimeInit$MethodAndArgsCaller.run(RuntimeInit.java:548)
06-25 18:06:21.606 19819 19819 E SystemServiceRegistry:         at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:1003)
06-25 18:06:21.608   648 20722 I DropBoxManagerService: add tag=system_app_wtf isTagEnabled=true flags=0x2
06-25 18:06:21.609   648 19639 W ActivityTaskManager:   Force finishing activity com.android.settings/.Settings
```
{% end %}

AOSP docs has some info on the [Settings architecture](https://source.android.com/docs/core/settings/info-architecture).
According to the stacktrace, the Settings Dashboard fragment calls `updateState` on each preference controller, and the `DeviceNamePreferenceController` attempts to get the WiFI system service:
```Java,name=packages/apps/Settings/src/com/android/settings/deviceinfo/DeviceNamePreferenceController.java
mWifiManager = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
```

This service is registered by the `SystemServer` if the WiFi feature is enabled:
```Java,name=frameworks/base/services/java/com/android/server/SystemServer.java
  if (context.getPackageManager().hasSystemFeature(
          PackageManager.FEATURE_WIFI)) {
      // Wifi Service must be started first for wifi-related services.
      t.traceBegin("StartWifi");
      mSystemServiceManager.startServiceFromJar(
              WIFI_SERVICE_CLASS, WIFI_APEX_SERVICE_JAR_PATH);
```
