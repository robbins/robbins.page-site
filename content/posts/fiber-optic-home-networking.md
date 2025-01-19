+++
title = "Deploying fiber optic networking in my home"
date = "2024-12-13"

[taxonomies]
tags=["networking", "fiber-optics"]
+++

- Explain SFP+ transceivers
- Explain FS box
- Explain SFP+ NICs
- Explain the trouble in finding white cables

# Introduction
I recently moved into a new house, and as usual was preparing to run some CAT6a cabling to get wired internet access on certain devices. The house already had some keystone jacks in the wall with
CAT6 cabling running to the basement, but they weren't in ideal locations. I didn't have full access to the basement, and the house didn't have an attic, so I needed to take the easy way out
and just run some cable along the moulding and baseboards. My existing CAT6 cabling was black, and it needed to be white in order to blend in. So, if I'm going to be buying and running
new cabling anyways, why not go fiber?

# Why not fiber?
- I'm not planning on a network connection greater than 10Gbps, even on LAN, in the near to distant future.
- Fiber transceivers are expensive, and my PC already has a 2.5Gbps 8P8C port.
- Nobody sells white fiber optic cable

# Why fiber?
- Well, mostly because it was fun.
- Switches with SFP+ ports are much cheaper than equivalents with 10GBASE-T ports. The same goes for NICs.
- Fiber optic cabling is cheaper than CAT6a
- Future proofing?

# Cabling
In order for my cabling to blend in along the baseboards, it needed to be white. This is a super common color for CAT6a cabling - but not for fiber. Since fiber optic cables are often color coded to
denote the type of fiber (e.g. single-mode vs multi-mode, OM3 vs OM4, etc.), it's not common to see white outer jackets. Some companies allowed custom outer jacket color, but they often only had
colors like red, yellow, or green. I couldn't find white anywhere. FS.com would sell me a custom order, but the minimum order quantity was a kilometer! 

But then I remembered that I just moved, and Bell had ran a long fiber cable from one wall of my house where the fiber line comes in, to the other where the modem was. Could I use that cabling?
That fiber patch cable had plenty of excess, as the technicians simply use pre-terminated lengths instead of fusion-splicing them in the customers home, and, most importantly, it was white, 
presumably to accomplish the same goal I had - to blend in inside a home.

From reading the labelling, I learned that this was single mode simplex fiber with SC/APC connectors from [OFS optics](https://fiber-optic-catalog.ofsoptics.com/G-657-B3-SM-Ultra-Bend-Insensitive-2-5-mm-minimum-bend-radius--1704), 
aptly named EZ-Bend Ultra Bend Insensitive, as this cable was stapled along the baseboard, made >90 degree turns, and was even pinched between a cabinet door. The website says it's meant to be compatible
with traditional copper wire installation processes, and it's crazy the fiber is able to survive all of this abuse and still have a usable signal come out the end.

# Transceivers
Normally, fiber is run as 2 pairs, or duplex, for full-duplex communication, where one strand is used for TX and the other for RX. However, I only had one cable. Luckily, bi-directional transceivers exist, 
which use 2 different wavelengths of light inside the same cable, which gets demuxed at the end back into 2 separate data streams. 
I went with these [10GBASE-BX BiDi SFP+ 1270nm-TX/1330nm-RX 10km Simplex LC/UPC](https://www.fs.com/products/42385.html), and note that they have to be purchased in matching pairs so that the
RX and TX frequencies are swapped on each ends.

# More cabling
The fiber cable I have uses SC/APC connectors, but the SFP+ transceivers use LC/UPC connectors, which aren't compatible. So I also had to buy some [SC/APC couplers](https://www.fs.com/products/76106.html)
and some [LC/UPC to SC/APC patch cable](https://www.fs.com/products/42046.html).

# NICs
I went with a cheap but reliable option (that still had modern Linux kernel support), Intel X520 NICs.

# Making it all work together
Now that I have the cable for the main run, cables to connect it to the transceivers on each end, and a NIC for my PC, it should just be plug and play, right? Upon plugging the transceiver into
my X520 NIC, I was met with this message:
```shell
[   13.050528] ixgbe 0000:02:00.0: failed to load because an unsupported SFP+ or QSFP module type was detected.
[   13.052026] ixgbe 0000:02:00.0: Reload the driver after installing a supported module.
[   13.052785] ixgbe: probe of 0000:02:00.0 failed with error -95
```

There is a kernel parameter that should allow the driver to work with 'unsupported' SFP+ modules, `allow_unsupported_sfp=1`, but even with this set, the modules still didn't work.

The other issue was that the modules weren't even detected in my Brocade ICX 6610 switch at all - the ports showed up as empty. I then learned that these switches also didn't recognize bi-directional
transceivers. What's going on here?

## SFP+ EEPROM
Network switch and SFP+ manufacturers like to use the EEPROM vendor fields on the transceiver to enforce compatibility. If the name doesn't match, the transceiver won't work. That's why you'll often see
stores that allow you to pick a brand at checkout. But they don't actually stock transceivers from every single brand.

### EEPROM re-programming
I figured that if I could change the vendor name to report as Intel (or Brocade, to enable optical link monitoring), and the part number to show up as a 10GBASE-LR transceiver, they should both work fine.
In theory, the electrical connections on the other end are the same whether the transceiver is bi-directional or not - why should the switch or NIC care about the optical medium?

After some failed attempts with `ethtool` which didn't let me access the EEPROM:
```shell
root@OpenWrt:~# ethtool --driver eth2
driver: mtk_soc_eth
version: 6.6.63
firmware-version:
expansion-rom-version:
bus-info: 15100000.ethernet
supports-statistics: yes
supports-test: no
supports-eeprom-access: no
supports-register-dump: no
supports-priv-flags: no
```

I came across SFP+ transceiver programmers. I bought my transceivers from FS.com, and they have one too, called the FS Box. The only problem is that it costs $700. After thinking that I might have
to buy an [SFP breakout board](https://shop.sysmocom.de/SFP-breakout-board-v1-kit/sfp-bo-v1-kit), I saw a little link called "I want one for free" on the FS Box product page. Two days later and I had
a transceiver programmer at my door! I switched the vendors and product names, and both transceivers were successfully detected! FS.com support was surprised after I told them the link was up and working
at 10Gbps - apparently it's not supposed to support changing types like that.

# Conclusion
I now have a 10Gbps link to my switch, which only has a 3Gbps link to the WAN. But at least I got an extra 500Mbps over the port on my motherboard. Was it worth it? Definitely.
