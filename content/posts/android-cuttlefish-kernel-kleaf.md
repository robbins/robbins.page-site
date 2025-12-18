+++
title = "Building Android kernel modules for Cuttlefish with Bazel"
date = "2024-08-26"

[taxonomies]
tags=["android", "linux", "cuttlefish"]
+++

The Android Open Source Project (AOSP) has long had an emulator, called [goldfish](https://android.googlesource.com/platform/external/qemu/+/emu-master-dev/android/docs/GOLDFISH-VIRTUAL-HARDWARE.TXT), (and later `ranchu`),
so that developers could test their code. However, it was based on QEMU, like the Android emulator that came with the Android SDK for regular app development, and it wans't ideal for platform development.
More recently, Google created the Cuttlefish emulator, which is a first-class citizen in AOSP that uses CrosVM & Virtio instead, and aims to deliver an experience identical to testing AOSP on a physical device.

After reading Nathan Chancellor's [excellent post](https://nathanchance.dev/posts/building-using-cuttlefish/) on how it easy it is to swap out the kernel on Cuttlefish, I decided to give building the kernel and a simple "Hello World" kernel module a shot, as the process has changed since then.

# Building Android & Running Cuttlefish
{{ note(header="Cuttlefish Prerequisites!", body="Unlike `goldfish`, Cuttlefish requires some host setup for it to run. I won't cover it in this blog post as I had to do some special setup for NixOS as it's not yet packaged in nixpkgs, but you can follow Google's documentation [here](https://source.android.com/docs/devices/cuttlefish/get-started).") }}

Cuttlefish can either be run from prebuilt artifacts from the AOSP CI, which saves a lot of disk space & CPU time, or it can be run from a local AOSP repo checkout.
I'm going to focus on the latter, as that's what I'm using, but you can refer to the above link for information on running from prebuilts.

As the main focus of this blog post is the kernel side of things, I'll only briefly go through the steps to build AOSP, but you can follow a more detailed tutorial [here](https://source.android.com/docs/setup/start) to setup your machine and build environment, and build the code.
```bash
# Get the code from all the different repositories
$ repo init -u https://android.googlesource.com/platform/manifest -b main
$ repo sync -j8
# Build for the x86_64 Cuttlefish target
$ . build/envsetup.sh
$ lunch aosp_cf_x86_64_phone-trunk_staging-userdebug
$ m
```

After waiting almost an hour and a half for a clean build to complete, we can finally run Cuttlefish with the `launch_cvd` command and check out the kernel version:
```Bash
$ adb shell
vsoc_x86_64:/ # cat /proc/version
Linux version 6.6.30-android15-6-g0643e9e3d6b1-ab11895514 (kleaf@build-host) (Android (11368308, +pgo, +bolt, +lto, +mlgo, based on r510928) clang version 18.0.0 (https://android.googlesource.com/toolchain/llvm-project 477610d4d0d988e69dbc3fae4fe86bff3f07f2b5), LLD 18.0.0) #1 SMP PREEMPT Tue May 28 15:59:07 UTC 2024
```

Looks like we're running version 6.6.30 from the `android15` branch.
```Make,name=device/google/cuttlefish/vsoc_x86_64_pgagnostic/BoardConfig.mk
# Use 6.6 kernel
TARGET_KERNEL_USE ?= 6.6
TARGET_KERNEL_ARCH ?= x86_64
SYSTEM_DLKM_SRC ?= kernel/prebuilts/$(TARGET_KERNEL_USE)/$(TARGET_KERNEL_ARCH)
TARGET_KERNEL_PATH ?= $(SYSTEM_DLKM_SRC)/kernel-$(TARGET_KERNEL_USE)
KERNEL_MODULES_PATH ?= kernel/prebuilts/common-modules/virtual-device/$(TARGET_KERNEL_USE)/$(subst _,-,$(TARGET_KERNEL_ARCH))
```

# Building The `android-mainline` Kernel
Let's switch it up a bit and compile `android-mainline` - all the supported kernel versions can be found [here](https://source.android.com/docs/setup/reference/bazel-support).
Recent Android kernel versions are now built solely with Bazel, as part of a project called [Kleaf](https://android.googlesource.com/kernel/build/+/refs/heads/master/kleaf/docs/kleaf.md).
Previously, a `build.sh` Bash script was used, but it became hard to maintain.

These steps are also mostly taken from Google's documentation [here](https://source.android.com/docs/setup/build/building-kernels).
This build process is entirely hermetic, meaning all dependencies, toolchains, etc. for the build are provided as part of the repo checkout, and no other tools are required (aside from `repo` to actually download the code).
To download and build the kernel, run:
```bash
# Get the code
$ repo init -u https://android.googlesource.com/kernel/manifest -b common-android-mainline
$ repo sync
# Build the virtual_device_x86_64 target which is what Cuttlefish runs
$ tools/bazel run //common-modules/virtual-device:virtual_device_x86_64_dist
```

{% detail(title="View source tree", default_open=false) %}
```Bash
> ls -l
total 44
drwxr-xr-x  4 4096 Aug 24 19:29 build # Bazel
drwxr-xr-x 26 4096 Aug 25 21:17 common # The Android Common Kernel source code
drwxr-xr-x  4 4096 Aug 24 19:29 common-modules # External kernel modules
drwxr-xr-x 21 4096 Aug 24 19:29 external # Bazel & other libraries
drwxr-xr-x  5 4096 Aug 24 19:29 kernel # Bazel build configs
lrwxrwxrwx  1   44 Aug 24 19:29 MODULE.bazel -> build/kernel/kleaf/bzlmod/bazel.MODULE.bazel
drwxr-xr-x  4 4096 Aug 26 06:46 out
drwxr-xr-x 12 4096 Aug 24 19:30 prebuilts # Clang, GCC, JDK, NDK, etc.
drwxr-xr-x  4 4096 Aug 24 19:29 test
drwxr-xr-x  3 4096 Aug 24 19:29 tools # mkbootimg for creating Android boot.img's
```
{% end %}

This build provides us with (among other things), an initramfs (`./out/virtual_device_x86_64/dist/initramfs.img`) and the kernel image itself (`./out/virtual_device_x86_64/dist/bzImage`).
Now we can simply tell Cuttlefish to boot using these files:

From the root of the AOSP source tree (in the same terminal you ran `m` from):
```bash
launch_cvd --noresume \
  -initramfs_path ../path-to-kernel/../out/virtual_device_x86_64/dist/initramfs.img \
  -kernel_path ../path-to-kernel/../out/virtual_device_x86_64/dist/bzImage
```

Make sure to pass the `-noresume` flag to ensure that a new instance is spawned and the new kernel is used.

```
vsoc_x86_64:/ # cat /proc/version
Linux version 6.10.0-mainline-maybe-dirty (kleaf@build-host) (Android (11967740, +pgo, +bolt, +lto, +mlgo, based on r522817) clang version 18.0.1 (https://android.googlesource.com/toolchain/llvm-project d8003a456d14a3deb8054cdaa529ffbf02d9b262), LLD 18.0.1) #1 SMP PREEMPT Thu Jan  1 00:00:00 UTC 1970
```
We can see that we're running the new kernel now.

# Building our custom kernel module
Our goal for this will be to write a simple "Hello World" style kernel module that will be included in the build of the above kernel Bazel target.

First, let's create our kernel module. From the root of your kernel checkout, create the following:
```c,name=vendor/hello_world.c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

static int hello_world_init(void)
{
   printk(KERN_ALERT "Hello World!\n");
   return 0;
}

static void hello_world_exit(void)
{
   printk(KERN_ALERT "Goodbye World!\n");
}

module_init(hello_world_init);
module_exit(hello_world_exit);

MODULE_LICENSE("GPL");
```
Super simple, it just prints a message to the kernel log when the module is loaded and unloaded.

Next, we need to create a `vendor/BUILD.bazel` so that the build system can build our module.
Kleaf provides the [Driver Development Kit](https://android.googlesource.com/kernel/build/+/refs/heads/main/kleaf/docs/ddk/main.md),
or DDK, which allows you to define kernel modules in the Bazel build system.
The bare minimum to build a standalone kernel module is the following:
```bazel
load("//build/kernel/kleaf:kernel.bzl",
    "ddk_module",
)

filegroup(
    name = "hello_world_sources",
    srcs = [
        "hello_world.c",
    ],
)

ddk_module(
    name = "hello_world",
    srcs = [":hello_world_sources"],
    out = "hello_world.ko",
    kernel_build = "//common-modules/virtual-device:virtual_device_x86_64",
)
```

If you're not familiar with Bazel, the `load` statement imports the functions we use in the rest of the file.
We then define a filegroup, although this isn't really necessary in this simple example since we only have 1 source file.
Then we define our actual kernel module itself, providing the target name, source files, and output.
We also specify the kernel build target, which I believe is necessary for Bazel to construct & use a consistent build environment.

We also need to make the `//common-modules/virtual-device:virtual_device_x86_64` target visibile to the `BUILD.bazel` in our `vendor` package. Edit `common-modules/virtual-device/BUILD.bazel` and add the following visibility argument to the `kernel_build` target with `name = "virtual_device_x86_64`:
```bazel
kernel_build(
    name = "virtual_device_x86_64",
    # ...
    visibility = [
        "//vendor:__pkg__",
    ],
)
```

With this, we can now run `tools/bazel build //vendor:hello_world` to compile the kernel and get our resulting kernel module: `bazel-bin/vendor/hello_world/hello_world.ko`.
Loading it manually shows that it worked correctly:
```
$ adb push bazel-bin/vendor/hello_world/hello_world.ko /data/local/tmp/
vsoc_x86_64:/data/local/tmp # insmod hello_world.ko
vsoc_x86_64:/data/local/tmp # dmesg | grep -i 'world'
[  552.722954] Hello World!
vsoc_x86_64:/data/local/tmp # rmmod hello_world.ko
vsoc_x86_64:/data/local/tmp # dmesg | grep -i 'world'
563.261902] Goodbye World!
```

But we'd like to have our modules loaded into the kernel automatically. 
To do so, we can create a `kernel_module_group` and add that to the `kernel_modules_install` target of our kernel build, `//common-modules/virtual-device:virtual_device_x86_64`, by adding the following:

```bazel,name=vendor/BUILD.bazel
load("//build/kernel/kleaf:kernel.bzl", "kernel_module_group")

kernel_module_group(
    name = "vendor_external_kernel_modules",
    srcs = [
        ":hello_world"
    ],
    visibility = ["//common-modules/virtual-device:__pkg__"],
)
```

Make sure to set the visibility so that this target will be available in the `common-modules/virtual-device` package.

Then, add this group:
```bazel,name=common-modules/virtual-device/BUILD.bazel
kernel_modules_install(
    name = "virtual_device_x86_64_modules_install",
    kernel_build = ":virtual_device_x86_64",
    kernel_modules = [
        ":virtual_device_x86_64_external_modules",
        "//vendor:vendor_external_kernel_modules",
    ],
)
```

Now, we can build the entire kernel with our modules with `tools/bazel run //common-modules/virtual-device:virtual_device_x86_64_dist`.
Verifying that it worked (running Cuttlefish with the same command as above to make it use our kernel):
```bash
vsoc_x86_64:/ # lsmod | grep hello_world
hello_world            12288  0
```

# Conclusion
As someone who doesn't have experience with either the previous `build.sh` method of building Android kernels, or the Bazel build system,
I found this process easy enough to understand after playing around with some things, reading some beginner Bazel documentation, and the [Bazel API reference](https://android.googlesource.com/kernel/build/+/refs/heads/main/kleaf/docs/api_reference) for the Android kernel. 
It took me a while to get to the simplest solution above, as there was some confusion around `//common:kernel_x86_64` and `//common-modules/virtual-device:virtual_device_x86_64`, the former
being the kernel build itself and the latter only defining kernel module build targets, as well as whether or not I needed rules to copy the module
to the distribution out directory, but the build rules for the other modules set all that up already, and so just modifying those is the easiest way to make additions.
