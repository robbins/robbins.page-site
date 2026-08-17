+++
title = "Reverse-engineering the FS Box SFP programmer to avoid using Windows"
date = "2026-06-12"

[taxonomies]
tags=["reverse-engineering", "networking"]
+++

# Introduction
The [FS Box](www.fs.com/products/156801.html) is an SFP/QSFP transceiver programmer. If you're not familiar with the world of enterprise networking, you might not know why such a product exists. SFP modules have an I2C EEPROM that stores information about their characteristics, as well as vendor information like part number, serial number, and manufacturer.
This vendor data is often used by switch manufacturers to restrict their equipment to only accepting certain brands of transceivers. SFP modules follow a standard, so I would say this restriction is never due to an actual technical reason. Thus, it's common to want to modify these EEPROM fields to bypass such limitations.

In theory, doing so is easy. For example, you can use a Raspberry Pi with an SFP HAT to interface with the I2C bus and read/write from/to the relevant addresses. In practice, many SFPs require a password to unlock the EEPROM for writing. Some general information on that process can be found [here](https://github.com/hfuller/transceiver-notes).

I wanted to see if there might be any useful information we can gain about these passwords, as well as fulfilling some curiosity I had about the FS Box, which I had used to sucessfully program some SFP modules from FS.com (which, apparently, are the only types of SFP modules it will accept without getting your account deactivated).

# Exploration
## Hardware
We start with the physical hardware itself:
{{ figure(src="./PCB_Top.jpeg", width=300, height=300, caption="PCB Top") }}
{{ figure(src="./PCB_Bottom.jpeg", width=300, height=300, caption="PCB Bottom") }}

Like I alluded to just above, it's very simple hardware. An STM32F407 microcontroller, the 4 SFP interfaces, a Bluetooth module, and that's pretty much it.

## Software
When you plug it via USB, it shows up as a HID device:
```Bash
usb 1-6.4: New USB device found, idVendor=4653, idProduct=4342, bcdDevice= 2.00
usb 1-6.4: New USB device strings: Mfr=1, Product=2, SerialNumber=3
usb 1-6.4: Product: FS Coding Box V4.5
usb 1-6.4: Manufacturer: Fiber Store
usb 1-6.4: SerialNumber: FSB0001
hid-generic 0003:4653:4342.004D: hiddev98,hidraw5: USB HID v1.01 Device [Fiber Store FS Coding Box V4.5] on usb-0000:0c:00.0-6.4/input0
```


Next, there is the [website](fsbox.com) that provides a GUI:
{{ figure(src="./Website.png", width=500, height=500, caption="fsbox.com") }}

And the 3rd part is an FS_Server driver that it complains isn't installed, and which only works on Windows or macOS (the macOS installer is just a downloader for a ZIP similar to the Windows direct download).

The box can connect via USB or via Bluetooth to your computer. There's also an Android app, which presumably does the same thing as the Windows driver, just over Bluetooth Low Energy. We can see the GATT characteristics in the decompiled Java sources.

If we download and unpack the `.msi` installer, we have the following:
```bash
├── Bootloader_F340.bin
├── default.json
├── FSBox.dll
├── FSBV3317.bin
├── FSBV4010.bin
├── FSBV4011.bin
├── FSBV4012.bin
├── FSBV4013.bin
├── FSBV4_2202.bin
├── FS_Coding_BOX_1_10.bin
├── fslog.ico
├── FS_Panel.exe
├── FS_Panel.exe.config
├── FS_Service.dll
├── FS_Update.exe
├── FS_Update.exe.config
├── HeadImg.png
├── HidSharp.dll
├── ICSharpCode.SharpZipLib.dll
├── InstallReg.dll
├── Log
│   ├── AbnormalMsg.LOG
│   └── Msg.LOG
├── Logo.png
├── MaterialDesignColors.dll
├── MaterialDesignThemes.Wpf.dll
├── Microsoft.AspNet.SignalR.Core.dll
├── Microsoft.AspNet.SignalR.SystemWeb.dll
├── Microsoft.Owin.Cors.dll
├── Microsoft.Owin.dll
├── Microsoft.Owin.Host.HttpListener.dll
├── Microsoft.Owin.Hosting.dll
├── Microsoft.Owin.Host.SystemWeb.dll
├── Microsoft.Owin.Security.dll
├── Newtonsoft.Json.dll
├── Owin.dll
├── SharpCompress.dll
├── System.Net.Http.dll
├── System.Net.Http.Formatting.dll
├── System.Web.Cors.dll
├── System.Web.Http.Cors.dll
├── System.Web.Http.dll
├── Utility.dll
└── VersionsFile
    ├── IsUpdateHardware.txt
    ├── md5.txt
    └── update_md5.txt
```

It looks like we have a couple of different versions of ARM Cortex-M firmware files for the STM32 microcontroller onboard (FSBV{3317,...,4013}.bin), as well as FSBV4_2202.bin, which seems to be different, and FS_Coding_BOX_1_10.bin and Bootloader_F340.bin, both of which `file` doesn't recognize.
We also have our FS_Service and FSBox DLLs that the website mentioned.

## Decompiling the DLLs
FSBox decompiled easily with ILSpy, but FS_Service was obfuscated with ConfuserEx2. 
For details on deobfuscating that you can refer to [this excellent YouTube video](https://www.youtube.com/watch?v=y_ma9cLFdmY), but the gist is to use dnSpy to dump the DLL once its been unpacked and loaded into memory, and then use a few other tools to decrypt strings.

Even still, these .NET DLLs practically decompile into source code, it's so incredibly readable and even nicer than Java - method names and even many local variable names are preserved.

```c#
public bool WriteFieldRaw(string address, byte startByte, byte[] data)
{
    if (data == null || data.Length == 0)
    {
        return false;
    }
    MODULE_Info iModule = Read_Module(0);
    switch (address)
    {
        case "A0":
        case "A2":
            return WriteFieldAligned(address, startByte, data, iModule);
        case "Page00h":
            if (!Table_Select(0, isSFP: false))
            {
                return false;
            }
            return WriteFieldAligned("A0", startByte, data, iModule);
...
}
```


# Communication on Linux without the FS driver
After looking through this for a little while, I had enough to write a POC for communicating with the box and receiving responses.
From what I can tell, the website sends messages to an ASP.NET SignalR server on `localhost:56789`, which gets processed by `FS_Service.dll`, and then `FSBox.dll` sends HID commands to the device and interprets the responses.
We can replicate these HID commands, but I no longer have a valid license for the web part, so we won't have access to any data that is only stored on their servers and sent over during programming.

## HID report structure
The HID report descriptor is:
```Bash
Usage Page (Vendor Page)
Usage (0x0001)
Collection (Application)
 Report ID (0x01)
 Report Count (64)
 Report Size (32)
 Physical Maximum (-1)
 Physical Minimum (0)
 Logical Maximum (-1)
 Logical Minimum (0)
 Usage (0x0004)
 Input (Data, Variable, Absolute, No Wrap, Linear, Preferred State, No Null position, Bit Field)
 Report ID (0x02)
 Report Count (64)
 Report Size (32)
 Physical Maximum (-1)
 Physical Minimum (0)
 Logical Maximum (-1)
 Logical Minimum (0)
 Usage (0x0006)
 Output (Data, Variable, Absolute, No Wrap, Linear, Preferred State, No Null position, Bit Field)
End Collection
```

It lists 2 reports, so we must specify `0x02` as the report ID for the output report. Then, we send it a `64*(32/4)=256` byte report (when I list indices, I'll skip the report ID byte).
Byte 0 is a checksum, byte 1 is the command, bytes 2-254 are data or 0, and then byte 255 is a sentinel value of `$`.
The full list of commands can be seen [here](https://github.com/robbins/fs-box-hid-linux/blob/59dbc534bea77105140349290ed72aa87392c9a0/refactor.py#L8).

## Challenge Response
The box attempts to ensure that it will only communicate with the official FS software, but it really only stops passive sniffing and replaying the commands.
Before any commands are accepted, the `Handle_Read` and `Handle_Check` commands must be sent and completed successfully. `Handle_Read` makes the box randomly generate and send back 4 values, which are to be used as indices (in the order of 1,3,2,0) into a long string of letters, numbers, symbols.
Both the driver and the microcontroller know this "key" string, and `Handle_Check` verifies that the 4 bytes the service sends back are the bytes at the generated indices.

## Getting responses
I've just plugged in an SFP module with nothing attached on the other end, and we can see some basic functionality:
{{ figure(src="./fs-box-sfp.jpeg", width=300, height=300, caption="FS Box with an SFP plugged in") }}

```
Fiber Store:FS Coding Box V4.5:FSB0001
REV: 4.0.0.2
SID: 0424100061
SFP Detected - RX LOS triggered
```

As an example of the commands, `02 24 FE 00 00 .. 00 00 24` turns off Bluetooth (Report ID, Checksum, Close_BLE command, Zeroes, Terminator).

At this point, all other functionality is simply a matter of translating the code from the DLLs to a custom implementation in whatever language you like, and maybe a fancy GUI to go along with it. That said, when other devices like the [SFP^2 Buddy](https://oopselectronics.com/product/SFP2) exist for EEPROM programming and much more, there's not much point to actually re-purposing these FS Boxes.
I got bored here, but this might be a great use case for an LLM! It could probably make short work of it and re-create all the functionality fairly easily.

# Microcontroller Firmware
```
FSBV4013.bin:           ARM Cortex-M firmware, initial SP at 0x2001dca0, reset at 0x0802019c, NMI at 0x08029934, HardFault at 0x080281fc, SVCall at 0x0802ab4c, PendSV at 0x08029b46
```
## Finding the base address
On STM-32 microcontrollers, flash is mapped at `0x08000000`, but the size of the entire binary is only `91556=0x165a4`, so a reset vector `0x2019c` bytes from the start of the file would be past the end.
We notice that `0x08020000` is a nice round number that sounds much more plausible, and indeed, loading it in at that address results in something sensible.

The firmware also sets the VTOR (address of the IVT) to that very address, and since it's typically located at the beginning of the binary, this is another sign we got it right.
```c
SCB_registers_t_e000ed00.vtor = (undefined *)&PTR_DAT_08020000;
```

It's also likely that flash is aliased and mapped at address `0x0` as well, where the MCU starts executing, so it's likely there was additional code loaded there, like a bootloader, that jumps to our application code.

## Custom decompression algorithm
After some standard STM-32 initialization code, the code then appears to copy this data into the start of SRAM:
```
000162d0: a4d6 0100 f005 0308 1011 4154 2b42 4155  ..........AT+BAU
000162e0: 443d 3131 3532 3030 0d0a 1911 4d53 4156  D=115200....MSAV
000162f0: 450a 4e52 4553 4554 0b58 0f44 4556 5f4e  E.NRESET.X.DEV_N
00016300: 414d 453d 424f 5834 2e2a 4808 4641 4354  AME=BOX4.*H.FACT
00016310: 4f52 590d 5d57 5354 412c 5e49 5343 4f4e  ORY.]WSTA,^ISCON
00016320: 4d4e 5441 5455 530c 480a 4144 563d 7374  MNTATUS.H.ADV=st
00016330: 6172 740f 1c4d 4143 0972 0112 fe12 0403  art..MAC.r......
00016340: 1001 0302 150b 6934 890e c912 8911 6a01  ......i4......j.
00016350: 0839 5a23 0104 1903 0113 1eb5 c002 08fd  .9Z#............
00016360: 041e 0dc1 0208 3104 1a6d 041a 8110 1ac5  ......1..m......
00016370: 0413 1201 3202 1640 5346 4243 1d02 0102  ....2..@SFBC....
00016380: 0354 1015 0403 0904 06a0 ff09 01a1 0185  .T..............
00016390: 0195 4075 2045 ff35 1425 ff15 bf09 0481  ..@u E.5.%......
000163a0: 0285 0212 1706 9102 c03c 011f 2059 0b02  .........<.. Y..
000163b0: 0855 041a 5d04 e11a 9052 49c6 72c8 00ff  .U..]....RI.r...
000163c0: 0061 4834 414e 675a 275d 6462 3066 7369  .aH4ANgZ']db0fsi
000163d0: 3c3f 603d 255b 344a 4f41 6e67 7259 5e26  <?`=%[4JOAngrY^&
000163e0: 2c72 5a55 646c 704e 614a 5b4c 4438 674d  ,rZUdlpNaJ[LD8gM
000163f0: 5671 4743 3d52 584c 7969 445f 4952 2652  VqGC=RXLyiD_IR&R
00016400: 4250 4a5f 3e72 5979 6a30 504a 5b4e 3d77  BPJ_>rYyj0PJ[N=w
00016410: 5158 5f46 775b 7132 316c 793d 6f21 6874  QX_Fw[q21ly=o!ht
00016420: 6877 2346 7276 3d37 722e 2f34 552a 3c2d  hw#Frv=7r./4U*<-
00016430: 2628 355e 2a7d 5070 6f43 723f 572f 7b73  &(5^*}PpoCr?W/{s
00016440: 402d 664d 7b6f 425d 422d 217a 4a54 5b4c  @-fM{oB]B-!zJT[L
00016450: 6c38 4750 2342 6158 5a46 736b 6a35 3d69  l8GP#BaXZFskj5=i
00016460: 4834 663c 3839 7148 2d3e 6968 5d6c 7a71  H4f<89qH->ih]lzq
00016470: 7843 7a6d 4740 7c58 7b4e 2967 7756 376b  xCzmG@|X{N)gwV7k
00016480: 3e4b 2d53 4a43 4e31 5f55 6954 303b 6e6a  >K-SJCN1_UiT0;nj
00016490: 4a29 702e 6325 5050 542c 3031 4863 5740  J)p.c%PPT,01HcW@
000164a0: 2623 5b6e 3a2f 346a 3267 3753 6e3a 5774  &#[n:/4j2g7Sn:Wt
000164b0: 2b4b 5729 5e38 4f41 3831 672d 6d32 74d3  +KW)^8OA81g-m2t.
000164c0: 573d 320a 450c 0240 1032 014a 0310 4240  W=2.E..@.2.J..B@
000164d0: 2915 2a30 0809 1010 4220 2a04 2c29 082b  ).*0....B *.,).+
000164e0: 0240 3b69 3f29 109a 021f 1114 1402 4039  .@;i?)........@9
000164f0: 3159 1329 1039 5179 5201 1112 942a 0101  1Y.).9QyR....*..
00016500: 017b 2a02 0101 7b2a 0301 0190 021e 0122  .{*...{*......."
00016510: 4132 402a bf09 114a be2e 34fe 0102 3808  A2@*...J..4...8.
00016520: fc88 7880 7801 0544 3a06 0632 073c f701  ..x.x..D:..2.<..
00016530: 080c 2209 3204 3527 1001 0a28 080b a080  ..".2.5'...(....
00016540: 8202 0488 4a01 1185 04ce 0120 6a10 9153  ....J...... j..S
00016550: 24f4 1ea5 bd02 0829 043c 5dbe 0257 1a5f  $......).<]..W._
00016560: 0c1e 7dbc 0208 8d04 c11a 8518 6904 1a95  ..}.........i...
00016570: 0414 0902 2913 0101 1ce0 f009 8533 0203  ....)........3..
00016580: 1b09 2110 1401 222c 1607 0581 0340 2d02  ..!...",.....@-.
00016590: 0705 0107 391a 4a11 1a31 3b0a 0613 3a40  ....9.J..1;...:@
000165a0: 84f1 0000                                ....
```

It starts off readable (is that an AT command I see?), but then quickly devolves into garbage. It turns out it wasn't copying the data, but decompressing it:
```c
undefined4 decompress_to(byte *src,byte *dst,int uncompressed_size)
{
  byte *sPtr;
  uint dstZeros;
  int copyLen2;
  uint copyLen1;
  byte *dstEnd;
  int srcByte;
  
  dstEnd = dst + uncompressed_size;
  do {
    srcByte = (int)*src;
    copyLen1 = srcByte & 0b00000111;
    sPtr = src + 1;
    if ((*src & 0b00000111) == 0) {
      sPtr = src + 2;
      copyLen1 = (uint)src[1];
    }
    dstZeros = srcByte >> 4;
    if (dstZeros == 0) {
      dstZeros = (uint)*sPtr;
      sPtr = sPtr + 1;
    }
    while (copyLen1 = copyLen1 - 1, copyLen1 != 0) {
      *dst = *sPtr;
      sPtr = sPtr + 1;
      dst = dst + 1;
    }
    if (srcByte << 28 < 0) {
      src = sPtr + 1;
      copyLen2 = dstZeros + 2;
      sPtr = dst + -(uint)*sPtr;
      while (copyLen2 = copyLen2 + -1, -1 < copyLen2) {
        *dst = *sPtr;
        dst = dst + 1;
        sPtr = sPtr + 1;
      }
    }
    else {
      while (dstZeros = dstZeros - 1, src = sPtr, -1 < (int)dstZeros) {
        *dst = 0;
        dst = dst + 1;
      }
    }
  } while (dst < dstEnd);
  return 0;
}
```

While I won't pretend to understand the compression algorithm used here (an LLM outputs that it's reminiscent of LZ77 + RLE), I recreated the logic in Python and successfully decompressed it:
```
00000000: 4154 2b42 4155 443d 3131 3532 3030 0d0a  AT+BAUD=115200..
00000010: 0041 542b 5341 5645 0d0a 0041 542b 5245  .AT+SAVE...AT+RE
00000020: 5345 540d 0a00 4154 2b44 4556 5f4e 414d  SET...AT+DEV_NAM
00000030: 453d 424f 5834 2e30 0d0a 0041 542b 4641  E=BOX4.0...AT+FA
00000040: 4354 4f52 590d 0a00 4154 2b57 5354 410d  CTORY...AT+WSTA.
00000050: 0a00 4154 2b44 4953 434f 4e0d 0a00 4154  ..AT+DISCON...AT
00000060: 2b53 5441 5455 530d 0a00 4154 2b41 4456  +STATUS...AT+ADV
00000070: 3d73 7461 7274 0d0a 0041 542b 4d41 430d  =start...AT+MAC.
00000080: 0a00 0100 0000 0000 0000 fe00 0400 0103  ................
00000090: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000000a0: 0b00 0000 0000 0000 0000 0000 0000 0000  ................
000000b0: 0000 0000 0000 0100 0000 0000 0000 0000  ................
000000c0: 0000 0000 0100 0000 0100 0000 0000 0000  ................
000000d0: 0000 0000 0000 0000 0001 0000 0000 0000  ................
000000e0: 0101 0000 0000 0000 0103 0000 0000 0104  ................
000000f0: 0000 0400 0000 0000 0000 0000 0000 0000  ................
00000100: 0000 0000 0000 0000 b5c0 0208 fdc0 0208  ................
00000110: 0dc1 0208 31c1 0208 6dc1 0208 81c0 0208  ....1...m.......
00000120: c5c0 0208 1201 0002 0000 0040 5346 4243  ...........@SFBC
00000130: 0002 0102 0301 0000 0403 0904 06a0 ff09  ................
00000140: 01a1 0185 0195 4075 2045 ff35 0025 ff15  ......@u E.5.%..
00000150: 0009 0481 0285 0295 4075 2045 ff35 0025  ........@u E.5.%
00000160: ff15 0009 0691 02c0 3c01 0020 590b 0208  ........<.. Y...
00000170: 550b 0208 5d0b 0208 0000 0000 0000 0000  U...]...........
00000180: 0000 0000 0000 9001 0000 0100 0000 0100  ................
00000190: c800 0000 0000 0000 6148 3441 4e67 5a27  ........aH4ANgZ'
000001a0: 5d64 6230 6673 693c 3f60 3d25 5b34 4a4f  ]db0fsi<?`=%[4JO
000001b0: 416e 6772 595e 262c 725a 5564 6c70 4e61  AngrY^&,rZUdlpNa
000001c0: 4a5b 4c44 3867 4d56 7147 433d 5258 4c79  J[LD8gMVqGC=RXLy
000001d0: 6944 5f49 5226 5242 504a 5f3e 7259 796a  iD_IR&RBPJ_>rYyj
000001e0: 3050 4a5b 4e3d 7751 585f 4677 5b71 3231  0PJ[N=wQX_Fw[q21
000001f0: 6c79 3d6f 2168 7468 7723 4672 763d 3772  ly=o!hthw#Frv=7r
00000200: 2e2f 3455 2a3c 2d26 2835 5e2a 7d50 706f  ./4U*<-&(5^*}Ppo
00000210: 4372 3f57 2f7b 7340 2d66 4d7b 6f42 5d42  Cr?W/{s@-fM{oB]B
00000220: 2d21 7a4a 545b 4c6c 3847 5023 4261 585a  -!zJT[Ll8GP#BaXZ
00000230: 4673 6b6a 353d 6948 3466 3c38 3971 482d  Fskj5=iH4f<89qH-
00000240: 3e69 685d 6c7a 7178 437a 6d47 407c 587b  >ih]lzqxCzmG@|X{
00000250: 4e29 6777 5637 6b3e 4b2d 534a 434e 315f  N)gwV7k>K-SJCN1_
00000260: 5569 5430 3b6e 6a4a 2970 2e63 2550 5054  UiT0;njJ)p.c%PPT
00000270: 2c30 3148 6357 4026 235b 6e3a 2f34 6a32  ,01HcW@&#[n:/4j2
00000280: 6737 536e 3a57 742b 4b57 295e 384f 4138  g7Sn:Wt+KW)^8OA8
00000290: 3167 2d6d 3274 573d 0000 0000 0000 0000  1g-m2tW=........
000002a0: 0000 0000 000a 0000 000c 0240 1000 0000  ...........@....
000002b0: 0001 0000 0003 0000 000c 0240 4000 0000  ...........@@...
000002c0: 0010 0000 0030 0000 0010 0240 4000 0000  .....0.....@@...
000002d0: 0010 0000 0030 0000 0010 0240 2000 0000  .....0.....@ ...
000002e0: 0004 0000 000c 0000 0004 0240 0100 0000  ...........@....
000002f0: 0100 0000 0300 0000 0004 0240 0200 0000  ...........@....
00000300: 0400 0000 0c00 0000 0014 0240 0020 0000  ...........@. ..
00000310: 0000 0004 0000 000c 0014 0240 0040 0000  ...........@.@..
00000320: 0000 0010 0000 0030 0000 0000 0000 0000  .......0........
00000330: 0000 0000 0000 0000 0000 0000 9400 0101  ................
00000340: 0101 0100 0000 0000 0000 0000 0000 0000  ................
00000350: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000360: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000370: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000380: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000390: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000003a0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000003b0: 0000 0000 0000 0000 0000 0000 0000 0202  ................
000003c0: 0202 0200 0000 0000 0000 0000 0000 0000  ................
000003d0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000003e0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000003f0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000400: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000410: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000420: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000430: 0000 0000 0000 0000 0000 0000 0000 0303  ................
00000440: 0303 0300 0000 0000 0000 0000 0000 0000  ................
00000450: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000460: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000470: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000480: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000490: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000004a0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000004b0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000004c0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000004d0: 0000 0001 0000 0000 0000 0000 0000 0000  ................
000004e0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000004f0: 0000 4100 0040 0000 00bf 0041 0000 00be  ..A..@.....A....
00000500: 0001 0000 0000 fe01 0200 0000 fc88 7880  ..............x.
00000510: 7801 0500 0000 0001 0600 0000 0001 0700  x...............
00000520: 0000 f701 0800 0000 0001 0900 0004 0000  ................
00000530: 0027 1001 0a00 0000 0ba0 8082 0204 8840  .'.............@
00000540: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000550: 0000 0000 04ce 0120 0000 0000 0000 0000  ....... ........
00000560: 1000 0000 0100 0000 0024 f400 0000 0000  .........$......
00000570: a5bd 0208 29bd 0208 5dbe 0208 0000 0000  ....)...].......
00000580: 5fbd 0208 7dbc 0208 8dbc 0208 0000 0000  _...}...........
00000590: 0000 0000 0000 0000 85bd 0208 85bd 0208  ................
000005a0: 85bd 0208 95bd 0208 0902 2900 0101 00e0  ..........).....
000005b0: f009 0400 0002 0300 0000 0921 0101 0001  ...........!....
000005c0: 222c 0007 0581 0340 0002 0705 0103 4000  ",.....@......@.
000005d0: 0200 0000 0921 1101 0001 222c 0000 0000  .....!....",....
000005e0: 0a06 0002 0000 0040 0100 0000 0000 0000  .......@........
000005f0: 0000 0000 0000 0000 0000 0000            ............
```

Tip: You can load this into Ghidra and have it analyze it for strings, pointers, etc. but I couldn't figure out how to overlay it on top of the existing SRAM block at `0x20000000`, so you have to cross-reference manually.

## Challenge-Response, Again
The block at `0x198` is the challenge-response data, and we can see the validation logic:
```c
command_also = hid_msg_recv_cmd;
if (command_also == Handle_Read) {
  uVar24 = GetRandomIndexForCR();
  ChallengeResponse_Index0 = uVar24;
  uVar24 = GetRandomIndexForCR();
  ChallengeResponse_Index1 = uVar24;
  uVar24 = GetRandomIndexForCR();
  ChallengeResponse_Index2 = uVar24;
  uVar24 = GetRandomIndexForCR();
  ChallengeResponse_Index3 = uVar24;
  bVar18 = ChallengeResponse_Index0;
  hid_response_buf[2] = bVar18;
  bVar18 = ChallengeResponse_Index1;
  hid_response_buf[3] = bVar18;
  bVar18 = ChallengeResponse_Index2;
  hid_response_buf[4] = bVar18;
  bVar18 = ChallengeResponse_Index3;
  local_10 = 6;
  hid_response_buf[5] = bVar18;
  uVar20 = EndIndexOfHidResponseBuf??;
  hid_response_buf[uVar20] = 0x50;
}
else if (command_also == Handle_Check) {
  bVar6 = hid_cmd_buffer[3];
  bVar18 = ChallengeResponse_Index1;
  if (bVar6 == ChallengeResponseData[bVar18]) {
    cr_response_byte = hid_cmd_buffer[4];
    bVar18 = ChallengeResponse_Index3;
    if (cr_response_byte == ChallengeResponseData[bVar18]) {
      bVar6 = hid_cmd_buffer[5];
      bVar18 = ChallengeResponse_Index2;
      if (bVar6 == ChallengeResponseData[bVar18]) {
        bVar6 = hid_cmd_buffer[6];
        bVar18 = ChallengeResponse_Index0;
        if (bVar6 == ChallengeResponseData[bVar18]) {
          bVar18 = DAT_200000b6;
          local_10 = 3;
          hid_response_buf[2] = bVar18;
          uVar20 = EndIndexOfHidResponseBuf??;
          hid_response_buf[uVar20] = 0x50;
          HandleCheck_CR_Completed? = 1;
          goto LAB_08032d3a;
        }
      }
    }
  }
  uVar20 = EndIndexOfHidResponseBuf??;
  hid_response_buf[uVar20] = 0x4e;
  HandleCheck_CR_Completed? = 0;
}
```
It's what I already knew, just a bit harder to figure out, but slightly easier than it would've been since I already knew what I was looking for.

## Next Steps
The AT commands, presumably for the Bluetooth module, are still to be investigated. There are also some pointers in the decompressed data to functions, so the structure of how it's all used should be looked at as well.

# (Unfortunate) Conclusions
It doesn't look like there's any special sauce that the FS Box hardware requires from the website / FS.com servers to work as a basic SFP programmer, provided all the commands were re-implemented.
However, it seems likely that the EEPROM passwords are sent server-side, as I haven't come across any sort of lookup table for them. 
The easiest way to check would be to sniff the network traffic and HID commands but I no longer have a valid license, and I'm sure it could be done by just reading the decompiled DLL code a bit more.
I've published my initial POC for the HID setup & communication [here](github.com/robbins/fs-box-hid-linux) on GitHub.
