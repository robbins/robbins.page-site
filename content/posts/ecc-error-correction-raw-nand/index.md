+++
title = "Decoding BCH codes from raw NAND flash for a Broadcom SOC"
date = "2026-08-18"

[taxonomies]
tags=["reverse-engineering", "hardware-hacking", "nand", "linux"]
+++

{{ note(header="Disclaimer", body="This started out as mostly a summation of pre-existing information on this topic but I thought it might be useful to have a demonstration of the practical applications and my process, as I tried to do this for the first time knowing hardly anything, mis-steps included. And while there were many, I ending up finding and fixing a bug in the tool I was using, so it ending up being even more useful than I'd thought!") }}

# Context / Tangent
This all started when I decided to follow the excellent [pon.wiki](https://pon.wiki/) to replace my ISP's modem/router/AP combination with my own equipment.
Their guides, along with the excellent [8311 Discord](https://pon.wiki/discord/) and some very helpful members, helped me achieve that goal.
Huge shoutout to @up-n-atom, as I gathered a huge amount of information combing through all the messages he's sent on that server :)

Bell's FTTH infrastructure uses a technology called PON, or Passive Optical Network, and
at its most basic, it involves the ONT on the customers premises communicating and authenticating with the OLT at the ISPs central office.

Now, I definitely don't have enough networking experience to understand GEM, TCONT, or the multitude of other acronyms used, but it got me curious about
how the community was able to figure all this out in general, and for Bell Canada in particular.

There's a whole history to Bell Home Hub / GigaHub exploration, involving a prototype unit sold at auction before release, 
a root exploit on the 3K & 4K using the (removed in a later update) XML config dump/restore feature, [convenient serial port jigs](https://github.com/up-n-atom/hubrxtx),
and [more](https://github.com/up-n-atom/sagemcom-modem-scripts).

So, these devices have already been studied fairly extensively, at least for the goal of a bypass, but after taking apart a GigaHub and realizing the
serial port seemed to be disabled, I decided to practice with my hot air station and take the chip off, which takes us to the point of this post.

# Chip-off
The chip, a S34ML04G200BHI000, came off easily with hot air - there was no underfill or anything. Unlike eMMC, this is just a raw NAND chip, so there's
no controller in the middle that we can talk to. I found that the easiest way was to use a programmer like the Xgecu T76, which
uses an FPGA to interface with a [huge list (HTTP-only link)](http://www.xgecu.com/MiniPro/T76_List.txt) of supported ICs. It has slightly sketchy software,
but there's an open-source project called [minipro](https://gitlab.com/DavidGriffith/minipro) which you can use on Linux.

The flash chip implements the Open NAND Flash Interface (ONFI) standard, and the programmer was able to query its info and read out the contents of the chip.
```
Flash Size: 557056KB
Page Size: 2048
Spare Size: 128
Page Per Block: 64
Total Blocks: 4096
```

{{ figure(src="xgecu.jpeg", width=300, height=50, caption="Chip in the socket") }}

# Binwalk
Binwalk seemed to be able to find some partition/filesystem information (to be honest, I don't quite understand the stack of MTD->UBI->UBIFS),
```Bash
S34ML04G2_flashmain.BIN
------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DECIMAL                            HEXADECIMAL                        DESCRIPTION
------------------------------------------------------------------------------------------------------------------------------------------------------------------------
76458                              0x12AAA                            AES S-Box
78056                              0x130E8                            AES S-Box
215722                             0x34AAA                            AES S-Box
217320                             0x350E8                            AES S-Box
354986                             0x56AAA                            AES S-Box
356584                             0x570E8                            AES S-Box
495378                             0x78F12                            AES S-Box
497104                             0x795D0                            AES S-Box
634642                             0x9AF12                            AES S-Box
636368                             0x9B5D0                            AES S-Box
771818                             0xBC6EA                            AES S-Box
773544                             0xBCDA8                            AES S-Box
911082                             0xDE6EA                            AES S-Box
912808                             0xDEDA8                            AES S-Box
2228224                            0x220000                           UBI image, version: 1, image size: 165306368 bytes
167534592                          0x9FC6000                          UBI image, version: 1, image size: 68378624 bytes
235913216                          0xE0FC000                          UBI image, version: 1, image size: 36487168 bytes
272400384                          0x103C8000                         UBI image, version: 1, image size: 36347904 bytes
308748288                          0x12672000                         UBI image, version: 1, image size: 35512320 bytes
344260608                          0x14850000                         UBI image, version: 1, image size: 29106176 bytes
373366784                          0x16412000                         UBI image, version: 1, image size: 26320896 bytes
399687680                          0x17D2C000                         UBI image, version: 1, image size: 92471296 bytes
492158976                          0x1D55C000                         UBI image, version: 1, image size: 40108032 bytes
532267008                          0x1FB9C000                         UBI image, version: 1, image size: 24371200 bytes
556638208                          0x212DA000                         UBI image, version: 1, image size: 7798784 bytes
564436992                          0x21A4A000                         UBI image, version: 1, image size: 5570560 bytes
```

but wasn't able to extract it.
```Bash
[-] Extraction of ubi data at offset 0x220000 failed!
[-] Extraction of ubi data at offset 0x9FC6000 failed!
[-] Extraction of ubi data at offset 0xE0FC000 failed!
[-] Extraction of ubi data at offset 0x103C8000 failed!
[-] Extraction of ubi data at offset 0x12672000 failed!
[-] Extraction of ubi data at offset 0x14850000 failed!
[-] Extraction of ubi data at offset 0x16412000 failed!
[-] Extraction of ubi data at offset 0x17D2C000 failed!
[-] Extraction of ubi data at offset 0x1D55C000 failed!
[-] Extraction of ubi data at offset 0x1FB9C000 failed!
[-] Extraction of ubi data at offset 0x212DA000 failed!
[-] Extraction of ubi data at offset 0x21A4A000 failed!
```

# Datasheet & ECC
The datasheet contains just 2 pages on error management, most of it dedicated to bad blocks, which is entirely separate from ECC. Bad blocks occur after a certain
number of erase-program cycles and must be tracked, but ECC is used to correct reads as they happen since its susceptible to noise and reads can affect
adjacent pages.

Furthermore, since there's no controller on the die to do the ECC like there would be with eMMC, it can either be performed by software,
in which case UBoot and Linux both need to implement it, or the SOC can do it in hardware, which, according to what I could find online, was the most likely.

The datasheet does mention "ECC (4 bit / 512+16 byte)", but I didn't really understand that at the time.

In agreement with the XGecu output, we can see that a page consists of 2048 bytes of data and 128 bytes of spare / OOB area. Blocks are 64 pages each, and
each plane is made up of 2048 blocks.

Looking at a hexdump of our file, we can indeed see the data and the distinctive spare area.

{{ figure(src="block0page0.png", width=300, height=50, caption="Block 0 page 0 data and spare") }}

## Attempt 1: Just remove the OOB data
My first attempt was just to strip out the OOB data, removing the 128 bytes at the end of each page and leaving just the data.
This did improve Binwalk's performance a lot - I was able to extract UBIFS images for most of the partitions, and they contained perfectly normal looking files.
```bash
[+] Extraction of ubi data at offset 0x200000 completed successfully
[+] Extraction of ubi data at offset 0x9660000 completed successfully
[+] Extraction of ubi data at offset 0xD3C0000 completed successfully
[+] Extraction of ubi data at offset 0xF480000 completed successfully
[+] Extraction of ubi data at offset 0x11520000 completed successfully
[+] Extraction of ubi data at offset 0x13500000 completed successfully
```

But I couldn't just leave it like that.

## A slight detour
I did some research on decoding NAND ECC, but nothing seemed concrete. Projects like [brcm-nand-bch](https://github.com/ak-hard/brcm-nand-bch)
made it clear that this had been looked into, and I'd heard of all the terms used, from syndrome, to linear code, but nothing seemed concrete.
That project also only implemented the encoding, not the decoding, and mentioned a large number of parameters that were required:
> For a particular type of sector, the first 9 1/2 bytes are always the same, and the last 52 bits are random. A 52-bit BCH ECC can be generated by a degree-13 BCH algorithm with T=4 (13 x 4 = 52).
Although this information is valuable, it does not necessary allows us to generate the correct code because there are several ways the algorithm can be used, such as how many bits are included in ECC, their alignment, and also bit order and possibly additive constants applied to the result (e.g. XOR-ing). Another required piece of information, the initial BCH polynomial, is also unknown.

I didn't have enough information to proceed at the time, so it sort of got put to the side - until I got another Bell device. This time, it was
a Home Hub 4000, which, while seeming to be extremely similar to the GigaHub, had its serial console enabled. With that and instructions
from the 8311 Discord, I was able to (essentially) do the classic `init=/bin/sh` trick from UBoot, mount the filesystem, and enable SSH.

```
> ssh root@192.168.2.1
root@mynetwork:~# id
uid=0(root) gid=0(root)
```

Nice (for future reference, because looking back on my notes I have no idea how I found this), the password is the value of 
Vendor-Info1 in the `permanent_params` partition.

## Getting more information
Now with access to this HH4K, I was able to get much more information about the NAND.

UBoot logs:
```Bash
NAND ECC BCH-4, page size 0x800 bytes, spare size used 64 bytes
NAND flash device: Spansion S34ML04G1, id 0x000001dc block 128KB size 524288KB
```

Linux kernel logs:
```Bash
nand: device found, Manufacturer ID: 0x01, Chip ID: 0xdc
nand: AMD/Spansion S34ML04G2
nand: 512 MiB, SLC, erase size: 128 KiB, page size: 2048, OOB size: 128
bcm63xx_nand ff801800.nand: Adjust timing_1 to 0x6532845b timing_2 to 0x00091e94
bcm63xx_nand ff801800.nand: detected 512MiB total, 128KiB blocks, 2KiB pages, 16B OOB, 8-bit, BCH-4
Bad block table found at page 262080, version 0x01
Bad block table found at page 262016, version 0x01
```

Device tree:
```
	nand {
		#address-cells = <0x01>;
		#size-cells = <0x00>;
		compatible = "brcm,nand-bcm63xx", "brcm,nand-bcmbca", "brcm,brcmnand-v7.1";
```

This tells us that:
- The Linux `brcmnand` driver is in use, which doesn't do software ECC, confirming that it's done in hardware
- We have controller version v7.1
- The ECC algorithm used is BCH-4, which can correct 4 bit errors per codeword
- Only 64B of the 128B OOB area is in use
- We have 16B of OOB data...? (I thought we had 64...)

Let's remind ourselves of the OOB data again:
```
00000800  FF FF FF FF FF FF FF FF  FF E5 BD BC D2 78 B2 D0  .............x..
00000810  FF FF FF FF FF FF FF FF  FF DB F0 E7 A2 BA 93 6F  ...............o
00000820  FF FF FF FF FF FF FF FF  FF E9 83 3F A8 C9 D9 B8  ...........?....
00000830  FF FF FF FF FF FF FF FF  FF C4 83 89 D0 7B 49 0C  .............{I.
00000840  FF FF FF FF FF FF FF FF  FF FF FF FF FF FF FF FF  ................
00000850  FF FF FF FF FF FF FF FF  FF FF FF FF FF FF FF FF  ................
00000860  FF FF FF FF FF FF FF FF  FF FF FF FF FF FF FF FF  ................
00000870  FF FF FF FF FF FF FF FF  FF FF FF FF FF FF FF FF  ................
```

We can see that the 2nd half seems to be padding, leaving only 4 groups of 16 bytes.

I then came across this excellent README for [BCH-Primitive-Polynomial-Search](https://github.com/giahuy2201/BCH-Primitive-Polynomial-Search), which explains
that each codeword is 512B long, with 16B of associated OOB data.

I then found [this blog post](https://claroty.com/team82/research/avayas-ip-phone-security-research-part-a) in which they 
provide explanations of the required parameters and use a fork of the earlier brcm-nand-bch repo which can do decoding. This was really the key in
helping me understand the process.

The fork they linked seems to have been deleted, but I found a [fork of it](https://github.com/hwti/brcm-nand-bch) that I could use.

It turns out that this device is modern enough that the parameters set already line up with our NANDs configuration:
```c
#define BCH_T 4
#define BCH_N 13
#define SECTOR_SZ 512
#define OOB_SZ 16
#define SECTORS_PER_PAGE 4
#define OOB_ECC_OFS 9
#define OOB_ECC_LEN 7
```

- It's BCH-4
- Math reasons mean N must be 13
- Each codeword or "sector" is 512 bytes of data with 16 bytes of OOB
- Our pages are 2048 bytes, which is 4 512-byte sectors
- The first 9 bytes are 0xFF padding, and the remaining 7 bytes are ECC data

# Finally decoding our NAND flash dump
It turns out we got lucky and we actually don't need to find or change any of these parameters. The default generator polynomial was correct as well.
However, running the decoder script on my NAND dump still wasn't producing a file that could be binwalked any better than before.

Using [this fork](https://github.com/liqili/brcm-nand-bch) which updated the encoding parameters for controller versions >= 5.0, I set the OOB data to 0xFF
and re-generated it. I noticed it was correct for the first block, but then it started highlighting the entire rest of the file as different... not just the
OOB regions.

The problem is that we defined the OOB region to be 16 bytes per codeword and that we have 4 codewords (=64 bytes) but our OOB section has an extra 64B of padding.
So, the steps to follow are:

1. Dump the NAND
2. Truncate the OOB region of each page to 64 bytes from 128 bytes
3. Decode the flash dump
4. Strip out the OOB regions, leaving only the data in each page
5. Successfully binwalk

```
> cat S34ML04G2_flashmain.bin.ecc-shortened | ./decode 0x5803 > decoded-shortened.out
4 bit errors in sector 0 of page 2079: 3249 329 2512 1040
4 bit errors in sector 0 of page 2143: 3249 329 2512 1040
4 bit errors in sector 3 of page 29911: 3574 2659 855 3364
3 bit errors in sector 1 of page 31717: 1159 111 49
4 bit errors in sector 0 of page 33060: 3580 1751 2555 3096
4 bit errors in sector 2 of page 39243: 1819 2578 2383 600
4 bit errors in sector 0 of page 39785: 265 522 1606 837
4 bit errors in sector 2 of page 40530: 2157 3435 1033 3937
4 bit errors in sector 2 of page 41140: 1143 3067 2023 3658
4 bit errors in sector 0 of page 43947: 2803 2180 3153 3585
4 bit errors in sector 1 of page 45646: 2361 706 548 3655
4 bit errors in sector 0 of page 48830: 2739 1531 1878 2999
4 bit errors in sector 3 of page 48987: 1242 3614 3902 2224
4 bit errors in sector 3 of page 50395: 3958 549 450 2708
4 bit errors in sector 0 of page 51046: 1067 641 1948 3809
4 bit errors in sector 1 of page 51551: 2687 1561 4200 3888
4 bit errors in sector 0 of page 54560: 2663 423 264 2351
4 bit errors in sector 1 of page 55909: 2909 128 4072 1227
4 bit errors in sector 3 of page 59287: 3574 2659 855 3364
4 bit errors in sector 0 of page 60814: 691 2759 4060 2270
3 bit errors in sector 1 of page 61093: 1159 111 49
4 bit errors in sector 0 of page 63606: 2092 1046 3210 3195
4 bit errors in sector 2 of page 65076: 1722 3095 831 1811
4 bit errors in sector 1 of page 65174: 3570 1099 3007 3592
4 bit errors in sector 1 of page 67238: 4082 3535 3533 969
4 bit errors in sector 1 of page 68183: 902 2842 1668 287
4 bit errors in sector 1 of page 70056: 2196 570 3358 2295
4 bit errors in sector 2 of page 84395: 2725 1164 4108 3740
4 bit errors in sector 2 of page 87032: 2028 2448 2006 1842
4 bit errors in sector 1 of page 87340: 2589 224 2592 4122
4 bit errors in sector 0 of page 92582: 2444 3446 3306 3049
4 bit errors in sector 3 of page 92848: 738 2423 326 4065
4 bit errors in sector 3 of page 93115: 147 1532 3416 2964
4 bit errors in sector 2 of page 94171: 61 727 1818 559
4 bit errors in sector 0 of page 157921: 1527 1730 2664 3010
4 bit errors in sector 0 of page 185896: 3201 1179 1210 3230
4 bit errors in sector 1 of page 205672: 2330 2532 3154 2187
4 bit errors in sector 0 of page 243678: 1717 1202 4065 951
```

It seems like we're really pushing the limits of our ECC - one more bit error in any of those 512B regions and we wouldn't be able to correct it! (Spoiler for the rest of the article: we weren't).

# Verifying our work (is something wrong?)
We can re-encode the data and compare to see if we're generating the right ECC bytes:
```
> cat S34ML04G2_flashmain.bin.ecc-shortened | ./reencode 0x5803 > verify.out
errors in sector 3 of page 12096
errors in sector 1 of page 22656
errors in sector 1 of page 35206
errors in sector 2 of page 65531
errors in sector 1 of page 66154
errors in sector 3 of page 93918
errors in sector 2 of page 106112
errors in sector 3 of page 115264
errors in sector 2 of page 168192
errors in sector 2 of page 201489
errors in sector 2 of page 210048
errors in sector 2 of page 226659
poly 22531 different OOB sectors: 12
```

Unfortunately, it seems like 12 sectors have different ECC data than we're generating. To be honest, I have no idea why this is, since it either works or it doesn't.
Maybe we had one too many bit errors in a segment like I alluded to above? I may try re-reading the chip and seeing if I get a different result, but for now,
it looks like we're as close as we can get. The Binwalk output is much better, and is including whole files it missed before, like the Linux kernel image,
so I'll call it a success.

## Update - Reading the chip again (and something's definitely wrong)
I am even more confused now than I was earlier. I spun up a Windows VM to run the Xgpro software and read the chip, and after re-calculating the ECC
bytes for this new read:
```
poly 22531 different OOB sectors: 22
```

Why did the number of different sectors almost double? I went back to the software and noticed it has an option for bit flip permission:
{{ figure(src="bit-flip-permission.png", width=800, height=100, caption="Bit Flip Permission") }}

This seems to be used in the "Verify" function, which reads the chip a second time and compares the two reads, considering it a pass if there are less than
n bit errors per m-byte segment, which the ECC can successfully correct. But this methodology seems flawed to me, because the read we're comparing against
isn't the ground truth but could also contain bit flips -- so a sector could easily have more than 4 bit errors compared to the ground truth, which
is what actually matters. For example, having 4 bit flips in a sector on the first read, and then 5 bit flips on the second.

Nevertheless, I noticed the Verify step was set to 8b/512B whereas my NAND ECC can only correct 4b/512B, so I changed the setting but the verification still passed.
I then disabled the setting entirely, and across 2 separate reads, it reports:
```
Block#437 Verify error Bytes: 1
Block#2501 Verify error Bytes: 1
Verify Error Blocks: 2
```

I guess it can only compare bytes and not bits, but this means there was at most 8 bits different in an entire block, which is 64 pages, or over 130,000 bytes.
NAND bit flips *aren't* independent, so I suppose it is more likely than random chance that > 4 could be in a single 512-byte region, but even with 16 bit flips,
we couldn't even have 12 or 22 different sectors with more than 4 bit errors. Diffing 2 separate reads bit-by-bit myself, 
I found 9 sectors each with a single bit difference. So it seems like there's very low error variance between reads.

What's interesting is that I ran a read+verify a few times, and got 1 byte in Block#437 3 times and got this exact same result twice.

Looking at the specific sectors that had different calculated ECC values in our 2nd read, we see that every single sector that shows up in
the first read, shows up in the second read.
```
errors in sector 3 of page 12096
errors in sector 3 of page 20416
errors in sector 1 of page 22656
errors in sector 1 of page 35206
errors in sector 3 of page 36665
errors in sector 2 of page 65531
errors in sector 1 of page 66154
errors in sector 3 of page 93918
errors in sector 2 of page 106112
errors in sector 3 of page 115264
errors in sector 3 of page 127232
errors in sector 0 of page 140480
errors in sector 1 of page 157484
errors in sector 2 of page 168192
errors in sector 2 of page 172578
errors in sector 2 of page 189888
errors in sector 1 of page 190400
errors in sector 2 of page 201489
errors in sector 2 of page 210048
errors in sector 1 of page 210304
errors in sector 2 of page 226659
```

So it seems like our reads are far off from the ground truth value...

But if we look at the sectors where errors were reported:
```
4 bit errors in sector 0 of page 2079: 3249 329 2512 1040
4 bit errors in sector 0 of page 2143: 3249 329 2512 1040
4 bit errors in sector 3 of page 29911: 3574 2659 855 3364
3 bit errors in sector 1 of page 31717: 1159 111 49
4 bit errors in sector 0 of page 33060: 3580 1751 2555 3096
4 bit errors in sector 2 of page 39243: 1819 2578 2383 600
4 bit errors in sector 0 of page 39785: 265 522 1606 837
4 bit errors in sector 2 of page 40530: 2157 3435 1033 3937
4 bit errors in sector 2 of page 41140: 1143 3067 2023 3658
4 bit errors in sector 0 of page 43947: 2803 2180 3153 3585
4 bit errors in sector 1 of page 45646: 2361 706 548 3655
4 bit errors in sector 0 of page 48830: 2739 1531 1878 2999
4 bit errors in sector 3 of page 48987: 1242 3614 3902 2224
4 bit errors in sector 3 of page 50395: 3958 549 450 2708
4 bit errors in sector 0 of page 51046: 1067 641 1948 3809
4 bit errors in sector 1 of page 51551: 2687 1561 4200 3888
4 bit errors in sector 0 of page 54560: 2663 423 264 2351
4 bit errors in sector 1 of page 55909: 2909 128 4072 1227
4 bit errors in sector 3 of page 59287: 3574 2659 855 3364
4 bit errors in sector 0 of page 60814: 691 2759 4060 2270
3 bit errors in sector 1 of page 61093: 1159 111 49
4 bit errors in sector 0 of page 63606: 2092 1046 3210 3195
4 bit errors in sector 2 of page 65076: 1722 3095 831 1811
4 bit errors in sector 1 of page 65174: 3570 1099 3007 3592
4 bit errors in sector 1 of page 67238: 4082 3535 3533 969
4 bit errors in sector 1 of page 68183: 902 2842 1668 287
4 bit errors in sector 1 of page 70056: 2196 570 3358 2295
4 bit errors in sector 2 of page 84395: 2725 1164 4108 3740
4 bit errors in sector 2 of page 87032: 2028 2448 2006 1842
4 bit errors in sector 1 of page 87340: 2589 224 2592 4122
4 bit errors in sector 0 of page 92582: 2444 3446 3306 3049
4 bit errors in sector 3 of page 92848: 738 2423 326 4065
4 bit errors in sector 3 of page 93115: 147 1532 3416 2964
4 bit errors in sector 2 of page 94171: 61 727 1818 559
4 bit errors in sector 0 of page 157921: 1527 1730 2664 3010
4 bit errors in sector 0 of page 185896: 3201 1179 1210 3230
4 bit errors in sector 1 of page 205672: 2330 2532 3154 2187
4 bit errors in sector 0 of page 243678: 1717 1202 4065 951
```

**they're identical**. Ok, something's definitely wrong now.

## The code has a bug
What I didn't realize the first time I did this, however, is that these two outputs don't correlate. The sets of pages that errors are detected in and pages errors are corected in are entirely disjoint.
The detection of errors looks correct since many overlap with our initial read, but there has to be something wrong with the decoding. And indeed:
```diff
diff --git a/decode.c b/decode.c
index c83ba57..d420332 100644
--- a/decode.c
+++ b/decode.c
@@ -75,7 +75,7 @@ int main(int argc, char *argv[]) {

                 // Consume ECC
                 unsigned int errlocs[BCH_T];
-                int nerr = decode_bch(bch, buffer, SECTOR_SZ + OOB_ECC_OFS, sector_oob, NULL, NULL, &errlocs[0]);
+                int nerr = decode_bch(bch, buffer, SECTOR_SZ + OOB_ECC_OFS, sector_oob + OOB_ECC_OFS, NULL, NULL, &errlocs[0]);
                 if (nerr < 0) {
                     numdecodeerrors++;
                 } else if (nerr > 0) {
```

It was missing the offset and using the padding instead of the parity bytes. After re-writing the code myself to work with 128-byte spare regions (but still only 64-bytes used for ECC), I get an identical and very different result:
```
1 bit errors in sector 3 of page 12096: 1917
1 bit errors in sector 3 of page 20416: 3690
1 bit errors in sector 1 of page 22656: 1243
1 bit errors in sector 1 of page 35206: 356
1 bit errors in sector 3 of page 36665: 3384
1 bit errors in sector 2 of page 65531: 3297
1 bit errors in sector 1 of page 66154: 381
1 bit errors in sector 3 of page 93918: 2170
1 bit errors in sector 2 of page 106112: 719
1 bit errors in sector 3 of page 115264: 367
1 bit errors in sector 3 of page 127232: 1255
1 bit errors in sector 0 of page 140480: 2175
1 bit errors in sector 1 of page 157484: 3082
1 bit errors in sector 2 of page 168192: 4025
1 bit errors in sector 2 of page 172578: 707
1 bit errors in sector 2 of page 189888: 1929
1 bit errors in sector 1 of page 190400: 1726
1 bit errors in sector 2 of page 201489: 1359
1 bit errors in sector 2 of page 210048: 2296
1 bit errors in sector 1 of page 210304: 2111
1 bit errors in sector 2 of page 226659: 1567
```

These pages match where the errors were detected, and also make much more sense. This is SLC NAND, so it should be the most reliable due to having only 2 voltage states per cell -- 1 bit error in a page makes sense.
I was also able to confirm a few of these which were obvious in that they were bit flips in pages almost entirely filled with zeroes, so they stood out as likely invalid.

# Conclusions
The "verify" feature of XGPro is definitely less than useful - across 2 separate reads, it reports only a single error:
```
> cat read1/verify_log
Block#2501 Verify error Bytes: 1
> cat read2/verify_log
Block#437 Verify error Bytes: 1
```

but that's only because both reads have the exact same ~20 other errors:
```
> diff <(cat read1.bin | ./a.out 0x5803 2> >(sort) >/dev/null) <(cat read2.bin | ./a.out 0x5803 2> >(sort) >/dev/null)
21a22
> 1 bit errors at positions: 812
40a42
> Generated parity data for message 3 in page 27968 @ 60858368, block 437 differs

> cat read2.bin | ./a.out 0x5803 > /dev/null 2> >(wc -l)
44
> cat read1.bin | ./a.out 0x5803 > /dev/null 2> >(wc -l)
42
```
(2 lines per error)

So NAND bit flips seem to be highly correlated. 

And now that the bug is fixed, I can correct multiple dumps and get identical files.
