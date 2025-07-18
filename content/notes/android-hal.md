+++
title = "Android HIDL/AIDL HAL"
date = "2024-08-27"

[taxonomies]
tags=["android", "aosp"]
+++

# Introduction
At first glance, Android HALs seem fairly straightforward - they're an interface between hardware-specific code and higher-level client code, such as the Android framework. However, there are multiple
different ways that HALs can be implemented, with a pre-Treble and multiple post-Treble implementations and another split between HIDL and AIDL, and I always get mixed up between them. So I thought
I'd write a note/blog post explaining each type, along with examples, to make it easier to understand.

## Motivation
When I was porting TWRP to the Moto G50, a crucial step in getting successful decryption of the data partition is to ensure that `keymaster` and `gatekeeper` HALs were running. But taking a look at
the devices files, it wasn't clear what I needed (some files not shown for clarity):
```shell
> find . -name "*gatekeeper*"
./partitions_unpacked/super_img_unpacked/system_a_img/system/lib64/android.hardware.gatekeeper@1.0.so
./partitions_unpacked/super_img_unpacked/vendor_a_img/bin/hw/android.hardware.gatekeeper@1.0-service-qti
./partitions_unpacked/super_img_unpacked/vendor_a_img/lib64/hw/android.hardware.gatekeeper@1.0-impl-qti.so
./partitions_unpacked/super_img_unpacked/system_a_img/system/bin/gatekeeperd
./partitions_unpacked/super_img_unpacked/system_a_img/system/lib64/libgatekeeper_aidl.so
./partitions_unpacked/super_img_unpacked/system_a_img/system/lib/libgatekeeper.so
> find . -name "*keymaster*"
./partitions_unpacked/super_img_unpacked/vendor_a_img/bin/hw/android.hardware.keymaster@4.1-service-qti
./partitions_unpacked/super_img_unpacked/vendor_a_img/bin/hw/android.hardware.keymaster@4.0-service-qti
./partitions_unpacked/super_img_unpacked/vendor_a_img/lib64/libqtikeymaster4.so
./partitions_unpacked/super_img_unpacked/system_a_img/system/lib64/android.hardware.keymaster@3.0.so
./partitions_unpacked/super_img_unpacked/system_a_img/system/lib64/android.hardware.keymaster@4.0.so
./partitions_unpacked/super_img_unpacked/system_a_img/system/lib64/android.hardware.keymaster@4.1.so
```

What's an `impl` and a `service`? What's the one with no suffix at all? And why doesn't `keymaster` have an implementation? Hopefully this post can make all of this clear.

# Definitions
These are directly taken, simplified, or adapted from the [AOSP HAL Docs](https://source.android.com/docs/core/architecture/hal). We'll get into all of these in more detail later.
- HIDL: A **deprecated** language used to define HAL interfaces for communicating with hardware, independent of the programming language used to call them.
- AIDL: A replacement for HIDL
- HAL Interface: A common interface for communication between HAL clients and services
- HAL Client: A process that makes calls to the HAL service via the HAL interface
- HAL Service: Hardware specific code that implements a HAL interface
- HAL Server: The process implenting a HAL interface, used to distinguish between binderized and passthrough HALs
- Binderized HAL: HAL service that runs in a separate process from the client and uses Binder IPC to communicate with clients
- Passthrough HAL: HAL service that is loaded directly into the client process
