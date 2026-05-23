+++
title = "Running the AOSP Cuttlefish virtual device on NixOS"
date = "2026-05-22"

[taxonomies]
tags=["aosp", "linux", "cuttlefish"]
+++

I previously used Cuttlefish to test [kernel builds with Kleaf](@/posts/android-cuttlefish-kernel-kleaf.md) back in 2024, where I talked about Cuttlefish as the replacement for the previous AOSP emulator, and mentioned that it required some extra setup on NixOS, but didn't go into details in that post.
I decided it'd be good as a reference, so here's the steps to get it to work.

The Android build environment is huge, and relies heavily on FHS paths & prebuilt binaries such as the Clang toolchain, thus, the first step is using `buildFHSEnv` as is referenced by [the NixOS wiki](https://wiki.nixos.org/wiki/Android#Building_Android_on_NixOS). This function returns a derivation that produces a shell with the `/bin`, `/usr`, etc. folders
from the included packages symlinked into their respective FHS paths. I'm building the `16-qpr2-release` branch, and it needed a few changes to build successfully. My updated devShell can be found [here](https://gist.github.com/robbins/d1a092a9cb50ebfb71a6716b9b579bee), now in flake format. Just make sure to put it in a subdirectory of your AOSP checkout, unless you want all ~400GB to be copied into your Nix Store.

Another new addition to the AOSP build system is the use of nsjail for sandboxing, which resulted in errors like these:

```Bash
[E][2026-05-22T05:30:53+0000][1] newProc():232 execve('/bin/bash') failed: No such file or directory 
[F][2026-05-22T05:30:53+0000][1] runChild():485 Launching child process failed
[W][2026-05-22T01:30:53-0400][1368502] runChild():505 Received error message from the child process before it has been executed
[E][2026-05-22T01:30:53-0400][1368502] standaloneMode():275 Couldn't launch the child process
```

This appeared fairly late into the build, after a large number of targets had already been built, and only for the `[ 84% 146745/174619] //trusty/vendor/google/aosp/scripts:trusty_security_vm_x86_64.elf generate` target. Thanks to the FHS shell, `/bin/bash` does exist, but of course it's simply a symlink to the Nix Store.
I was able to fix this by applying the following patch to `build/soong` so that the Nix Store would be bind-mounted into the jail.

```Go
diff --git a/android/rule_builder.go b/android/rule_builder.go
index 88898f365..8dae9c579 100644
--- a/android/rule_builder.go
+++ b/android/rule_builder.go
@@ -667,6 +667,8 @@ func (r *RuleBuilder) build(name string, desc string) {
 		nsjailCmd.WriteString(" -R /lib64")
 		nsjailCmd.WriteString(" -R /dev")
 		nsjailCmd.WriteString(" -R /usr")
+		nsjailCmd.WriteString(" -R /nix/store")
+		nsjailCmd.WriteString(" -R /etc")

 		nsjailCmd.WriteString(" -m none:/tmp:tmpfs:size=1073741824") // 1GB, should be enough
 		nsjailCmd.WriteString(" -D nsjail_build_sandbox")
```

I also included `/etc` to solve the following error:
```Bash
error: linking with /nsjail_build_sandbox/prebuilts/clang/host/linux-x86/clang-r563880/bin/clang++ failed: exit status: 127
= note: /nsjail_build_sandbox/prebuilts/clang/host/linux-x86/clang-r563880/bin/clang++-real: error while loading shared libraries: libz.so.1: cannot open shared object file: No such file or directory
```

Like before `/usr/lib/libz.so.1` does exist, but the dynamic linker is only able to find it in the nsjail if I add `/usr/lib` to `LD_LIBRARY_PATH`:
```Bash
> prebuilts/build-tools/linux-x86/bin/nsjail -R /bin -R /lib -R /lib64 -R /usr -R /nix/store -R /aosp/android-latest-release/prebuilts -- /bin/bash -c 'ldd /aosp/android-latest-release/prebuilts/clang/host/linux-x86/clang-r563880/bin/clang++-real' 
[I][2026-05-22T12:30:28-0400] Jail parameters: hostname:'NSJAIL', chroot:'', process:'/bin/bash', bind:[::]:0, max_conns:0, max_conns_per_ip:0, time_limit:0, personality:0, daemonize:false, clone_newnet:true, clone_newuser:true, clone_newns:true, clone_newpid:true, clone_newipc:true, clone_newuts:true, clone_newcgroup:true, clone_newtime:false, keep_caps:false, disable_no_new_privs:false, max_cpus:0 
[I][2026-05-22T12:30:28-0400] Mount: '/' flags:MS_RDONLY type:'tmpfs' options:'' dir:true 
[I][2026-05-22T12:30:28-0400] Mount: '/bin' -> '/bin' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true 
[I][2026-05-22T12:30:28-0400] Mount: '/lib' -> '/lib' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true 
[I][2026-05-22T12:30:28-0400] Mount: '/lib64' -> '/lib64' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true 
[I][2026-05-22T12:30:28-0400] Mount: '/usr' -> '/usr' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true 
[I][2026-05-22T12:30:28-0400] Mount: '/nix/store' -> '/nix/store' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true
[I][2026-05-22T12:30:28-0400] Mount: '/aosp/android-latest-release/prebuilts' -> '/aosp/android-latest-release/prebuilts' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true 
[I][2026-05-22T12:30:28-0400] Mount: '/proc' flags:MS_RDONLY type:'proc' options:'' dir:true 
linux-vdso.so.1 (0x00007ffff7fc2000)
...
libz.so.1 => not found libgcc_s.so.1 => /nix/store/xx0z77494lfxr8qjwpck246fry05n3nm-xgcc-15.2.0-libgcc/lib/libgcc_s.so.1 (0x00007ffff7f7c000)
...
/lib64/ld-linux-x86-64.so.2 => /nix/store/fjkx1l5cnskzrqacf08z7i8z17256w0j-glibc-2.42-61/lib64/ld-linux-x86-64.so.2 (0x00007ffff7fc4000)

> prebuilts/build-tools/linux-x86/bin/nsjail -R /bin -R /lib -R /lib64 -R /usr -R /nix/store -R /aosp/android-latest-release/prebuilts -- /bin/bash -c 'LD_LIBRARY_PATH=/usr/lib ldd /aosp/android-latest-release/prebuilts/clang/host/linux-x86/clang-r563880/bin/clang++-real' 
[I][2026-05-22T12:30:28-0400] Jail parameters: hostname:'NSJAIL', chroot:'', process:'/bin/bash', bind:[::]:0, max_conns:0, max_conns_per_ip:0, time_limit:0, personality:0, daemonize:false, clone_newnet:true, clone_newuser:true, clone_newns:true, clone_newpid:true, clone_newipc:true, clone_newuts:true, clone_newcgroup:true, clone_newtime:false, keep_caps:false, disable_no_new_privs:false, max_cpus:0 
[I][2026-05-22T12:31:05-0400] Mount: '/' flags:MS_RDONLY type:'tmpfs' options:'' dir:true
[I][2026-05-22T12:31:05-0400] Mount: '/bin' -> '/bin' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true
[I][2026-05-22T12:31:05-0400] Mount: '/lib' -> '/lib' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true
[I][2026-05-22T12:31:05-0400] Mount: '/lib64' -> '/lib64' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true 
[I][2026-05-22T12:31:05-0400] Mount: '/usr' -> '/usr' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true
[I][2026-05-22T12:31:05-0400] Mount: '/nix/store' -> '/nix/store' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true
[I][2026-05-22T12:31:05-0400] Mount: '/aosp/android-latest-release/prebuilts' -> '/aosp/android-latest-release/prebuilts' flags:MS_RDONLY|MS_BIND|MS_REC|MS_PRIVATE type:'' options:'' dir:true 
[I][2026-05-22T12:31:05-0400] Mount: '/proc' flags:MS_RDONLY type:'proc' options:'' dir:true [I][2026-05-22T12:31:05-0400] Uid map: inside_uid:1000 outside_uid:1000 count:1 newuidmap:false
linux-vdso.so.1 (0x00007ffff7fc2000) 
...
libz.so.1 => /usr/lib/libz.so.1 (0x00007ffff7f8c000)
...
/lib64/ld-linux-x86-64.so.2 => /nix/store/fjkx1l5cnskzrqacf08z7i8z17256w0j-glibc-2.42-61/lib64/ld-linux-x86-64.so.2 (0x00007ffff7fc4000)
```

I'm assuming this is because `ldd` now has access to `/etc/ld.so.conf` which is also provided thanks to the FHSEnv, but according to `ldd(1)` that's only one of the many places it looks, and it's a standard path too, so it's possible it's something else.

Now that we have a successful build, it's time to run Cuttlefish. I will say that this is a bare-minimum setup for it, just enough to get it to run, but not with all functionality. The [AOSP instructions](https://source.android.com/docs/devices/cuttlefish/get-started) mention installing `cuttlefish-base` and `cuttlefish-user`, two custom Debian packages.
In fact, the only required file from these for Cuttlefish to start is `base/host/deploy/capability_query.py`. A quick derivation later (and some code to put it in the right place in the FHS environment, because otherwise it would be directly in `/bin`, instead of where it looks for it:

```Nix,name=cuttlefish-base.nix
{ stdenv, python3, fetchFromGitHub }:

stdenv.mkDerivation (finalAttrs: {
  pname = "cuttlefish-base";
  version = "latest";

  src = fetchFromGitHub {
    owner = "google";
    repo = "android-cuttlefish";
    rev = "bdc7b896a7ca4311468270b5e13971cd6d5ce6bd";
    sha256 = "sha256-a1TBemY6sB6OZdnq8DhHcrzMdX/lTPyMbvohaqmBFV8=";
  };

  buildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -av $src/base/host/deploy/capability_query.py $out/bin/

    runHook postInstall
  '';
})
```

```Nix,name=flake.nix
extraBuildCommands = ''
    mkdir -p $out/usr/lib64/cuttlefish-common
    cp -r ${self.packages.${system}.cuttlefish-base.out}/* $out/usr/lib64/cuttlefish-common
'';
```

and that's taken care of.

The Cuttlefish device also relies on the `cvdnetwork` group existing, and typically, being in the `kvm` group.

However, it seems like entering the FHSEnv sets all group membership to `nogroup`, except for the GID of your primary group:
```Bash
> groups
users nogroup
```

which results in `Failed to set group for path: /tmp/nix-shell.fCZfgj/cf_env_1000, cvdnetwork, Invalid argument`.

Luckily, we can just set our primary group temporarily with `newgrp cvdnetwork` before entering the shell, and then, assuming you've selected a target supported by Cuttlefish and run `m`, you can now run:
```Bash
HOME=/tmp/cuttlefish launch_cvd -enable_tap_devices "false" --vm_manager=qemu_cli -start_webrtc
```

I was getting a permission denied error when it tried to create TAP interfaces (something the cuttlefish-base package sets up), and the CrosVM backend gave an error about `Caused by: failed to create a PCI root hub: failed to create proxy device: Failed to configure tube: failed to receive packet: Connection reset by peer (os error 104)`.
The QEMU backend works, even without being a member of the `kvm` group for `/dev/kvm` access (don't ask me how), and the only downside is that the display doesn't work in the Web interface, meaning we have to connect via VNC instead.

But the device is up!
```Bash
vsoc_x86_64_only:/ # getprop ro.build.description
aosp_cf_x86_64_only_phone-userdebug 16 BP4A.251205.006 eng.nate test-keys
```
and we can see the device controls at localhost:8443 and the screen at localhost:6444 via a VNC client.
