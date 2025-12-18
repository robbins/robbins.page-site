+++
title = "Android HIDL/AIDL HAL"
date = "2024-08-27"
template = "post.html"

[taxonomies]
tags=["android", "aosp"]
+++

# Introduction
At first glance, Android HALs seem fairly straightforward - they're an interface between hardware-specific code (of which there are many) and higher-level client code (which would be nice if it was a single API), such as the Android framework. However, there are multiple
different ways that HALs can be implemented, with a pre-Treble and multiple post-Treble implementations and another split between HIDL and AIDL, and I always get mixed up between them. So I thought
I'd write a note/blog post explaining each type, along with examples, to make it easier to understand.

Some great Android architecture information (that I'll reference throughout) is [Opersys](https://opersys.com), who has a great [embedded Android](https://www.opersys.com/downloads/cc-slides/embedded-android/slides-main-clean) slide deck and acompanying videos on their [YouTube channel](https://www.youtube.com/@opersys).
Their [YouTube video](https://www.youtube.com/watch?v=UFaWqdxBW4E) on Android Treble is also a great reference, and honestly what I'm basing these notes on, but I'm writing it out to ensure
I can follow all of the connections and go into some more detail.

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
These are directly taken, simplified, or adapted from the [AOSP HAL Docs](https://source.android.com/docs/core/architecture/hal).
- HIDL: A **deprecated** language used to define HAL interfaces for communicating with hardware, independent of the programming language used to call them.
- AIDL: A replacement for HIDL, already used for framework<->app IPC
- HAL Interface: A common interface for communication between HAL clients and services
- HAL Client: A process that makes calls to the HAL service via the HAL interface
- HAL Service: Hardware specific code that implements a HAL interface
- HAL Server: The process implenting a HAL interface, used to distinguish between binderized and passthrough HALs
- Binderized HAL: HAL service that runs in a separate process from the client and uses Binder IPC to communicate with clients
- Passthrough HAL: HAL service that is loaded directly into the client process

# Legacy (pre-8.0) HALs
{{ figure(src="./pre-treble.png", alt="", caption="Pre-Treble architecture. Source: Opersys Embedded Android Slide Deck", width="500", height="300") }}
{{ figure(src="./pre-treble-2.png", alt="", caption="Pre-Treble architecture. Source: Opersys Embedded Android Slide Deck", width="200", height="300") }}

Google describes these HALs as having "rough versioning and a roughly stable ABI", but that they "never provided hard stability guarantees".

At the top level, we can see the Service Manager and the System Server.
The Android `system_server` is forked from Zygote and is responsible for starting the Java system services such as `ActivityManager`, `LightsService`, `PackageManager`, and eventually `SystemUI` (snippets):
```java,name=frameworks/base/services/java/com/android/server/SystemServer.java
private SystemServiceManager mSystemServiceManager;

/**
 * The main entry point from zygote.
 */
public static void main(String[] args) {
    new SystemServer().run();
}

private void run() {
    // Create the system service manager.
    mSystemServiceManager = new SystemServiceManager(mSystemContext);
    mSystemServiceManager.setRuntimeRestarted(mRuntimeRestart);
    LocalServices.addService(SystemServiceManager.class, mSystemServiceManager);
    mPowerManagerService = mSystemServiceManager.startService(PowerManagerService.class);

    startBootstrapServices();
    startCoreServices();
    startOtherServices();
}

private void startBootstrapServices() {
    mPowerManagerService = mSystemServiceManager.startService(PowerManagerService.class);
    mSystemServiceManager.startService(LightsService.class);
    mDisplayManagerService = mSystemServiceManager.startService(DisplayManagerService.class);
}

private void startOtherServices() {
    location = new LocationManagerService(context);
    ServiceManager.addService(Context.LOCATION_SERVICE, location);
    // It is now time to start up the app processes...
    wm.systemReady();
    mPackageManagerService.systemReady();
    mActivityManagerService.systemReady(new Runnable() {
        @Override
        public void run() {
            startSystemUi(context);
        }
}

static final void startSystemUi(Context context) {
    Intent intent = new Intent();
    intent.setComponent(new ComponentName("com.android.systemui",
                "com.android.systemui.SystemUIService"));
    intent.addFlags(Intent.FLAG_DEBUG_TRIAGED_MISSING);
    context.startServiceAsUser(intent, UserHandle.SYSTEM);
}
```

We see that system services can be directly initialized as an instance of the class, and then registered with the `ServiceManager` via calls to `addService(name, service)`. 

There are also calls to `mSystemServiceManager.startService(className)`, which creates the services using reflection.  The `SystemServiceManager` is used for services which need to handle lifecycle events
such as `onStart()`, `onStartUser()`, `onUnlockUser()`, `onBootPhase()`, etc, and the `SystemServer` triggers these callbacks as startup progresses.
These services are registered with the `ServiceManager` in the `onStart` callback.
Boot phases control what actions a service can perform at a certain point (e.g. call into other other services, broadcast intents, bind to 3rd-party apps, etc), and `SystemServer` triggers these

```java,name=frameworks/base/services/core/java/com/android/server/power/PowerManagerService.java
public void onStart() {
    publishBinderService(Context.POWER_SERVICE, new BinderService());
    publishLocalService(PowerManagerInternal.class, new LocalService());
}
```

```java,name=frameworks/base/services/core/java/com/android/server/SystemService.java
protected final void publishBinderService(String name, IBinder service,
        boolean allowIsolated) {
    ServiceManager.addService(name, service, allowIsolated);
}
```

## ServiceManager
Apps (running in different processes) talk to system services using Binder for IPC. The calling process, or client, invokes methods on a proxy, which are forwarded to the node in the remote process, or server.
```java,name=frameworks/base/core/java/android/os/ServiceManager.java
public static void addService(String name, IBinder service) {
    try {
        getIServiceManager().addService(name, service, false);
    } catch (RemoteException e) {
        Log.e(TAG, "error in addService", e);
    }
}
```

`addService()` expects an object of type IBinder. This is the server side, so it will be receiving an implemention of the `Stub` interface. 
In the case of services with lifecycle methods, such as `PowerManagerService`, it defines `PowerManagerService.BinderService` which extends `IPowerManager.Stub`:
```java,name=frameworks/base/services/core/java/com/android/server/power/PowerManagerService.java
private final class BinderService extends IPowerManager.Stub {
    @Override // Binder call
    public void reboot(boolean confirm, String reason, boolean wait) {
    }
}
```

For other services, they extend the stub directly:
```java,name=frameworks/base/services/core/java/com/android/server/LocationManagerService.java
public class LocationManagerService extends ILocationManager.Stub {
}
```

Services that are local-only, such as `LightsService`, do not implement a `Stub` interface and are only published as `publishLocalService`.

## AIDL API
Finally moving to the first inner box, the AIDL definitions are used generate the Java interface. This represents the contract between the Android framework and the system service.
```java,name=frameworks/base/core/java/android/os/IPowerManager.aidl
interface IPowerManager
{
    void reboot(boolean confirm, String reason, boolean wait);
}
```

//TODO:  Add ServiceManagerNative IServiceManager.aidl onTransact transact stuff and more binder in depth maybe

### Framework API
As an aside, the framework API defines:
```java,name=frameworks/base/core/java/android/os/PowerManager.java
public void reboot(@Nullable String reason) {
    try {
        mService.reboot(false, reason, true);
    } catch (RemoteException e) {
        throw e.rethrowFromSystemServer();
    }
}
```
which is where the Binder RPC call is made following the IPowerManager.aidl interface.

//TODO: How tf does mService get created cause I cannot find that mf

## Java/JNI/C++
The `mPowerManagerService` makes use of native C++ functions.
```java,name=frameworks/base/services/core/java/com/android/server/power/PowerManagerService.java
private native void nativeInit();
private static native void nativeAcquireSuspendBlocker(String name);
private static native void nativeReleaseSuspendBlocker(String name);
private static native void nativeSetInteractive(boolean enable);
private static native void nativeSetAutoSuspend(boolean enable);
private static native void nativeSendPowerHint(int hintId, int data);
private static native void nativeSetFeature(int featureId, int data);
```

Moving quicker now, we can then see where the HAL module is loaded and the calls to the native implementations:
```cpp,name=android-7.1.2_r39:frameworks/base/services/core/jni/com_android_server_power_PowerManagerService.cpp
struct power_module* gPowerModule;

static void nativeInit(JNIEnv* env, jobject obj) {
    status_t err = hw_get_module(POWER_HARDWARE_MODULE_ID, (hw_module_t const**)&gPowerModule);
    gPowerModule->init(gPowerModule);
}

static void nativeSetFeature(JNIEnv *env, jclass clazz, jint featureId, jint data) {
    if (gPowerModule && gPowerModule->setFeature) {
        gPowerModule->setFeature(gPowerModule, (feature_t)featureId, data_param);
    }
}
```

## Native HAL
Finally, we reach the HAL module definition and implementation. The `power.h` header file defines the contract between the framework and the Power HAL.
```c,name=hardware/libhardware/include/hardware/power.h
#define POWER_HARDWARE_MODULE_ID "power"
typedef struct power_module {
    struct hw_module_t common;
    void (*init)(struct power_module *module);
    void (*setFeature)(struct power_module *module, feature_t feature, int state);
    void (*setInteractive)(struct power_module *module, int on);
}
```

```c,name=hardware/libhardware/modules/power/power.c
static void power_init(struct power_module *module) {}

static void power_set_interactive(struct power_module *module, int on) {}

static void power_hint(struct power_module *module, power_hint_t hint, void *data) {
    switch (hint) {
    default:
        break;
    }
}

static struct hw_module_methods_t power_module_methods = {
    .open = NULL,
};

struct power_module HAL_MODULE_INFO_SYM = {
    .common = {
        .tag = HARDWARE_MODULE_TAG,
        .module_api_version = POWER_MODULE_API_VERSION_0_2,
        .hal_api_version = HARDWARE_HAL_API_VERSION,
        .id = POWER_HARDWARE_MODULE_ID,
        .name = "Default Power HAL",
        .author = "The Android Open Source Project",
        .methods = &power_module_methods,
    },

    .init = power_init,
    .setInteractive = power_set_interactive,
    .powerHint = power_hint,
};
```

and this is compiled into a shared library as follows:
```Makefile,name=hardware/libhardware/modules/power/Android.mk
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := power.default
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_SRC_FILES := power.c
LOCAL_SHARED_LIBRARIES := liblog
LOCAL_MODULE_TAGS := optional

include $(BUILD_SHARED_LIBRARY)
```

Going back to the defintion of `hw_get_module`, we see that the shared library is `dlopen`'ed by the system service, which runs in the system server.
```c,name=hardware/libhardware/hardware.c
int hw_get_module(const char *id, const struct hw_module_t **module)
{
    return hw_get_module_by_class(id, NULL, module);
}
int hw_get_module_by_class(const char *class_id, const char *inst, const struct hw_module_t **module)
{
    snprintf(prop_name, sizeof(prop_name), "ro.hardware.%s", name);
    if (property_get(prop_name, prop, NULL) > 0) {
        if (hw_module_exists(path, sizeof(path), name, prop) == 0) {
            goto found;
        }
    }

    /* Nothing found, try the default */
    if (hw_module_exists(path, sizeof(path), name, "default") == 0) {
        goto found;
    }

found:
    return load(class_id, path, module);
}
static int load(const char *id, const char *path, const struct hw_module_t **pHmi)
{
    void *handle = NULL;
    struct hw_module_t *hmi = NULL;

    handle = dlopen(path, RTLD_NOW);

    /* Get the address of the struct hal_module_info. */
    const char *sym = HAL_MODULE_INFO_SYM_AS_STR;
    hmi = (struct hw_module_t *)dlsym(handle, sym);

    hmi->dso = handle;

    *pHmi = hmi;
}
```

There are numerous disadvantages with this approach:
// TODO: discuss in depth and understand them w examples

//TODO: example of whats a Java system service vs a Native system service.

//TODO: how do we get from the java code to the JNI C++ code??
# Android 8.x HIDL Same-Process/Passthrough HALs
The ServiceManager side of things is mostly unchanged, so having gone through that once we'll skip it for Android 8.x.

Looking at the 8.1.0 `PowerManagerService`, we see that we still have our native methods:
```Java,name=frameworks/base/services/core/java/com/android/server/power/PowerManagerService.java
    private native void nativeInit();
    private static native void nativeAcquireSuspendBlocker(String name);
    private static native void nativeReleaseSuspendBlocker(String name);
    private static native void nativeSetInteractive(boolean enable);
    private static native void nativeSetAutoSuspend(boolean enable);
    private static native void nativeSendPowerHint(int hintId, int data);
    private static native void nativeSetFeature(int featureId, int data);
```

but some changes are made to the C++ side.

```cpp,name=android-8.1.0_r81:frameworks/base/services/core/jni/com_android_server_power_PowerManagerService.cpp
static void nativeInit(JNIEnv* env, jobject obj) {
    getPowerHal();
}
bool getPowerHal() {
    if (gPowerHalExists && gPowerHalV1_0 == nullptr) {
        gPowerHalV1_0 = android::hardware::power::V1_0::IPower::getService();
        if (gPowerHalV1_0 != nullptr) {
            gPowerHalV1_1 =  android::hardware::power::V1_1::IPower::castFrom(gPowerHalV1_0);
            ALOGI("Loaded power HAL service");
        }
    }
}
```

Instead of a call to `hw_get_module`, we now see a call to `getService()`.
