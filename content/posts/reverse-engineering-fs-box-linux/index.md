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
We start with the physical hardware itself:
{{ figure(src="./PCB_Top.jpeg", width=300, height=300, caption="PCB Top") }}
{{ figure(src="./PCB_Bottom.jpeg", width=300, height=300, caption="PCB Bottom") }}

Like I alluded to just above, it's very simple hardware. An STM32F407 microcontroller, the 4 SFP interfaces, a Bluetooth module, and that's pretty much it.

Next, there is the [website](fsbox.com) that provides a GUI:
{{ figure(src="./Website.png", width=500, height=500, caption="fsbox.com") }}

And the 3rd part is an FS_Server driver that it complains isn't installed, and which only works on Windows or macOS (the macOS installer is just a downloader for a ZIP similar to the Windows direct download).

The box can connect via USB or via Bluetooth to your computer. There's also an Android app, which presumably does the same thing as the Windows driver, just over Bluetooth Low Energy. We can see the GATT characteristics in the decompiled Java sources. Another place to look into later.

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

The `.bin` files look like ARM Cortex-M firmware, which I may investigate at a later date.

We can see our FS_Service and FSBox DLLs - FSBox decompiled easily with ILSpy, but FS_Service was obfuscated with ConfuserEx2. For details on deobfuscating that you can refer to [this excellent YouTube video](https://www.youtube.com/watch?v=y_ma9cLFdmY), but the gist is to use dnSpy to dump the DLL once its been unpacked and loaded into memory, and then a few other tools to decrypt strings.

These .NET DLLs practically decompile into source code, it's so incredibly readable and even nicer than Java - method names and even many local variable names are preserved.

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

# FS Box Architecture
From what I can see, the website sends messages to an ASP.NET SignalR server on `localhost:56789`, which gets processed by `FS_Service.dll`, and then `FSBox.dll` sends HID commands to the device and interprets the responses.

How the device appears in Linux:
```Bash
usb 1-6.4: New USB device found, idVendor=4653, idProduct=4342, bcdDevice= 2.00
usb 1-6.4: New USB device strings: Mfr=1, Product=2, SerialNumber=3
usb 1-6.4: Product: FS Coding Box V4.5
usb 1-6.4: Manufacturer: Fiber Store
usb 1-6.4: SerialNumber: FSB0001
hid-generic 0003:4653:4342.004D: hiddev98,hidraw5: USB HID v1.01 Device [Fiber Store FS Coding Box V4.5] on usb-0000:0c:00.0-6.4/input0
```

and its HID report descriptor:
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

# POC of Linux Support
After reading the decompiled DLLs, we can create a Python script to replicate the "challenge-response" flow and communicate with the FS Box from Linux, without needing their driver or the website.
It expects 257-byte payloads (+1 byte for the HID output report ID), where byte 1 is a checksum, byte 2 is the command, byte 3-255 is data or 0, and byte 256 is 0x24 ($).
The challenge-response would present a roadblock if we were just sniffing the USB communication, since it changes on every connection attempt, but we can just follow the logic from the DLLs. There isn't any cryptography going on.
For example, `02 24 FE 00 .. 00 24` turns off Bluetooth.

I've just plugged in an SFP module with nothing attached on the other end, and we can see some basic functionality:
{{ figure(src="./fs-box-sfp.jpeg", width=300, height=300, caption="FS Box with an SFP plugged in") }}

```
Fiber Store:FS Coding Box V4.5:FSB0001
REV: 4.0.0.2
SID: 0424100061
SFP Detected - RX LOS triggered
```

At this point, all other functionality is simply a matter of translating the code from the DLLs to a custom implementation in whatever language you like, and maybe a fancy GUI to go along with it. That said, when other devices like the [SFP^2 Buddy](https://oopselectronics.com/product/SFP2) exist for EEPROM programming and much more, there's not much point to actually re-purposing these FS Boxes.
I got bored here, but this might be a great use case for an LLM! It could probably make short work of it and re-create all the functionality fairly easily.

# (Unfortunate) Conclusions
There's no special sauce that the FS Box hardware requires from the website / FS.com servers to work as a basic SFP programmer. 
However, it seems like EEPROM passwords are sent server-side - I don't have an active license so didn't look at that side of things, although it would be doable just by reading the decompiled DLL code.
There's also the FS Box STM32 firmware itself that I may take a look at in the future, as well as the Android apps.
I've published my initial POC for the HID setup & communication [here](github.com/robbins/fs-box-hid-linux) on GitHub.
