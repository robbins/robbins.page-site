+++
title = "Extracting TPLink Switch Firmware Encryption Keys"
date = "2025-09-17"

[taxonomies]
tags=["reverse-engineering", "network-switch", "tp-link"]
+++

{{ note(header="Parallel Investigation", body="I'm posting this way after I wrote it, but right after I looked into this, so did [tangrs](https://blog.tangrs.id.au/2025/09/22/decrypting-tplink-smart-switch-firmware/). He found out that that the non-GPL system binaries are included in TP-Link's GPL source code dump, so the firmware can be analyzed and the firmware extracted without needing to own the hardware. I forked the TP-Link decryption project that I found while researching this encryption, and used @tangrs' method to support switch firmware decryption.") }}

# Introduction
I was recently in the market for a network switch with at least 4x 2.5G Base-T ports and 2x SFP+ 10G ports. One switch I came across was the TPLink Omada SG3210X-M2, which fit all my criteria
(managed, fanless, right number & types of ports, integrated power supply). Browsing the TPLink website, I came across the firmware files and was curious what they looked like. However, it turns out
they are encrypted. Can I figure out how to decrypt them?

# Switch Firmware
After downloading the firmware update file, I used the standard tools used for figuring out "what is this data"?
```bash
> file SG3210X-M2v1_en_1.0.3_\[20240528-rel72451\]_up.bin
SG3210X-M2v1_en_1.0.3_[20240528-rel72451]_up.bin: data

> strings SG3210X-M2v1_en_1.0.3_\[20240528-rel72451\]_up.bin
Gyy
        Wf_
<2m}'
6]>Dw
NXg$
l'rE
TFxL M_y
...

> binwalk SG3210X-M2v1_en_1.0.3_\[20240528-rel72451\]_up.bin
Analyzed 1 file for 85 file signatures (187 magic patterns) in 108.0 milliseconds
```

Not a good sign. Lets check out the entropy:
{{ figure(src="./SG3210X-M2v1_en_1.0.3_[20240528-rel72451]_up.bin.png", width=300, height=50, caption="Entropy") }}
It's either encrypted or compressed - let's do some research.

# Existing TP Link Firmware Encryption Research
[This excellent blog post](https://watchfulip.github.io/28-12-24/tp-link_c210_v2.html?utm_source=feedly) by WatchfulIP has done some excellent work on investigating, among other things, the encryption
of TP Link firmware encryption on other devices like cameras. It looks like they use RSA-2048 for signature verification which are in plaintext in the binary, and also generate AES keys to perform decryption.
Notably, the encryption/decryption library is published under the GPL, so we can use that along with keys extracted from the binary.

Unfortunately, this doesn't work for us, as it's mentioned that switch firmware is not supported. Taking a look at our firmware, it doesn't match the same structure as other firmware like the Tapo
camera.

WatchfulIP's blog post notes that the Tapo firmware starts with a header, which is used to determine encryption type, firmware version, etc:
```
> xxd Tapo_C210v1_en_1.3.1_Build_221218_Rel.73283n_u_1679534600836.bin | head
00000000: 0000 0100 55aa 4c5e 831f 534b a1f8 f7c9  ....U.L^..SK....
00000010: 18df 8fbf 7da1 aa55 0800 0000 0000 0017  ....}..U........
00000020: dfad 96ed 5333 eccc 8f66 8b33 9497 ad2b  ....S3...f.3...+
00000030: b0e7 ae6f 3853 6209 7ec1 7800 859f 9b68  ...o8Sb.~.x....h
00000040: eb31 5991 a42e e7d0 d914 3040 d681 f3ed  .1Y.......0@....
```

whereas our switch firmware doesn't seem to have that:
```
xxd SG3210X-M2v1_en_1.0.3_\[20240528-rel72451\]_up.bin | head
00000000: 4091 9d48 1d8c 65d2 2047 7979 848c f21f  @..H..e. Gyy....
00000010: 8260 6333 b16b 8679 4193 52e7 0957 665f  .`c3.k.yA.R..Wf_
00000020: b28c 4b76 51bc a65b b5a6 a62e 1259 b233  ..KvQ..[.....Y.3
00000030: 0849 ad07 e9ef fb7c 6235 b146 0e23 b0eb  .I.....|b5.F.#..
```

There doesn't seem to be a transition firmware either, as all firmware files listed for this switch are encrypted. Let's see if we can pull the firmware from the device itself.

# Hardware Hacking Time
Opening it up, we notice a Winbond W25Q256JV SPI flash in a 16-pin SOIC package.
{{ figure(src="top.jpg", width=300, height=50, caption="Top") }}
{{ figure(src="bottom.jpg", width=300, height=50, caption="Bottom") }}
Connecting to it with a combination of 8-pin SOIC clip + PCBite probes, and talking SPI with help from a Tigard, we can dump it with flashrom:
```bash
>sudo flashrom --programmer ft2232_spi:type=2232H,port=B,divisor=16 -c W25Q256JV_Q -r dump.bin
```

Let's see what we got:
```bash
> binwalk dump1.bin
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DECIMAL                            HEXADECIMAL                        DESCRIPTION
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
658948                             0xA0E04                            Copyright text: "Copyright (c) "
688288                             0xA80A0                            CRC32 polynomial table, little endian
1048640                            0x100040                           LZMA compressed data, properties: 0x5D, dictionary size: 67108864 bytes, compressed size: 4344242 bytes, uncompressed size: -1 bytes
7340032                            0x700000                           SquashFS file system, little endian, version: 4.0, compression: lzo, inode count: 67, block size: 131072, image size: 9017272 bytes,
                                                                      created: 2025-01-23 03:50:02
17825792                           0x1100000                          SquashFS file system, little endian, version: 4.0, compression: lzo, inode count: 67, block size: 131072, image size: 9017272 bytes,
                                                                      created: 2025-01-23 03:50:02
28311552                           0x1B00000                          JFFS2 filesystem, big endian, nodes: 134, total size: 4128780 bytes
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
```

Looks good!

We can extract the main SquashFS:
```bash
extractions/dump1.bin.extracted/1100000/squashfs-root/usrImage
├── app
│   └── sbin
│       ├── 2048_newroot.cer
│       ├── cli_server
│       ├── cloud-brd
│       ├── cloud_config.cfg
│       ├── cloud_service.cfg
│       ├── core
│       ├── ecs
│       ├── httpd
│       ├── monitor.cfg
│       ├── oemid_SG2210XMP_M2.json
│       ├── oemid_SG3210XHP_M2_V3.json
│       ├── oemid_SG3210X_M2.json
│       ├── oemid_SG3218XP_M2.json
│       ├── rmso.sh
│       ├── routed
│       ├── rtty
│       ├── scm
│       ├── snmpd
│       ├── tpsyslogd
│       └── tpsystemd
├── data
│   ├── ca.crt
│   ├── ca.key
│   ├── dynMenu.json
│   ├── switch_SG2210XMP_M2.tp
│   ├── switch_SG3210XHP_M2_V3.tp
│   ├── switch_SG3210X_M2.tp
│   ├── switch_SG3218XP_M2.tp
│   ├── switch.tp
│   ├── verify_pub.key
│   └── webImage.z
├── kmod
│   └── ethdriver.ko
└── lib
    ├── engines-1.1
    │   ├── capi.so
    │   └── padlock.so
    ├── libcrypto.so.1.1
    ├── libcurl.so.4 -> libcurl.so.4.7.0
    ├── libcurl.so.4.7.0
    ├── libgdsl.so.0
    ├── libipcom.so.0
    ├── libipcrypto.so.0
    ├── libipssh.so.0
    ├── libipssl2.so.0
    ├── libpal.so.0
    ├── libroute.so.0
    ├── libservice_core.so.0
    ├── libservice_mod.so.0
    ├── libservice_scm.so.0
    ├── libservice.so.0
    ├── libssl.so.1.1
    ├── libvx2linux.so.0
    └── pkgconfig
        ├── libcrypto.pc
        ├── libssl.pc
        └── openssl.pc
```

Looking for the word upgrade, we get a couple relevant hits:
```bash
> rg --binary -i "upgrade"
usrImage/app/sbin/core
usrImage/app/sbin/ecs
> file usrImage/app/sbin/core
usrImage/app/sbin/core: ELF 32-bit MSB executable, MIPS, MIPS32 rel2 version 1 (SYSV), dynamically linked, interpreter /lib/ld-uClibc.so.0, BuildID[sha1]=0ea327d20cb6903216bed5428da8800b147285cc, with debug_info, not stripped
```
Not stripped and debug info. Should be easy.

# (Barely) Reverse Engineering
Upon decompilation, we get one of the [nicest real-world decompilations](./ghidra1.png) I've ever come across. We have function names, data symbol names - this shouldn't be too hard.
Searching for symbols containing `upgrade`, we find the `swSysTftpFirmwareUpgrade` function. Cleaning it up a bit, we see that it calls `swFirmwareTftpUpgrade` to download the file over TFTP,
and then calls `swFirmwareUpgrade`.

`swFirmwareUpgrade` verifies the RSA signature using rsaVerifySignByBase64EncodePublicKeyBlob, which initially led me down the wrong path.
See, on other TPLink firmware, the function that verifies the signature is `rsaVerifyPSSSignByBase64EncodePublicKeyBlob` (note the PSS), and this function also performs decryption.
We have the same base64-encoded RSA key blob here, but it is only used for signature verification with RSA-1024 (the last 128 bytes of the file).

After stripping the 128-byte signature from the end of the file, the buffer gets passed to `sysUpgradeFirmware`, which calls `sysParseImage` from `libservice.so.0`.
We then see a call to the conveniently named `sysDesDecode` function, and wow, we're done:
```c
undefined4 sysDesDecode(int param_1,undefined4 param_2,int param_3)
{
  undefined4 uVar1;
  
  if ((param_1 == 0) || (param_3 == 0)) {
    uVar1 = 0;
  }
  else {
    des_decode(&des_key,&des_iv,param_1,param_2,param_3);
    uVar1 = 1;
  }
  return uVar1;
}
```

I didn't even have to name that `des_key` and `des_iv`.

# Conclusion
The TP Link SG3210X-M2 firmware files can be decrypted by any standard DES implementation, such as [this](https://gchq.github.io/CyberChef/#recipe=DES_Decrypt(%7B'option':'Hex','string':''%7D,%7B'option':'Hex','string':''%7D,'CBC/NoPadding','Hex','Raw'))
easy-to-use one, using the extracted key and IV in CBC mode with the NoPadding mode. It seems that other switch firmware also uses the same key/IV. Switch firmware decryption has also been added to [tp-link-decrypt](https://github.com/robbins/tp-link-decrypt).
