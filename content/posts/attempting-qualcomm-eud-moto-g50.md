+++
title = "Exploring Qualcomm EUD on Moto G50"
date = "2025-07-30"

[taxonomies]
tags=["android", "qualcomm"]
+++

# What is EUD?
Qualcomm EUD is a USB interface that allows access to multiple peripherals such as JTAG and SWD on Qualcomm SOCs. More information on it can be found in [this Linaro blog post](https://www.linaro.org/blog/hidden-jtag-qualcomm-snapdragon-usb/).
Enabling it brings up a custom USB hub that can be interacted with using Qualcomm's fork of OpenOCD.
According to the Linaro post, the device-side of it can be disabled via the QFPROM, or via an OEM-signed debug policy, which sometimes allows access even when fused off.
Let's see if we can access it on a production Moto G50.

# Is it even supported?
Let's check out the device tree by unpacking the vendor boot image to extract the device tree blob and decompile it.
```Bash
> unpack_bootimg --boot_img vendor_boot.img --out out
boot magic: VNDRBOOT
vendor boot image header version: 3
page size: 0x00001000
kernel load address: 0x00008000
ramdisk load address: 0x01000000
vendor ramdisk size: 1745
vendor command line args: androidboot.boot_devices=soc/4804000.ufshc androidboot.selinux=permissive androidboot.console=ttyMSM0,115200n8 androidboot.hardware=qcom androidboot.usbcontroller=4e00000.dwc3 printk.devkmsg=on androidboot.init_fatal_panic=true printk.always_kmsg_dump=1 androidboot.init_fatal_reboot_target=recovery buildvariant=eng
kernel tags load address: 0x00000100
product name:
vendor boot image header size: 2112
dtb size: 323520
dtb address: 0x0000000001f00000
```

```Bash
dtc -I dtb -O dts -o out/dts out/dtb
```

We do see the following device node for EUD, so that's one requirement.
```c,name=out/dts
qcom,msm-eud@1628000 {
	compatible = "qcom,msm-eud";
	interrupt-names = "eud_irq";
	interrupts = <0x00 0xbd 0x04>;
	reg = <0x1628000 0x2000 0x162a000 0x1000 0x3e5018 0x04>;
	reg-names = "eud_base", "eud_mode_mgr2", "eud_tcsr_check_reg";
	qcom,secure-eud-en;
	qcom,eud-tcsr-check-enable;
	status = "ok";
	phandle = <0x237>;
};
```
We have some registers which might come in handy, and a boolean property called `qcom,secure-eud-en`. What does that mean?

Downloading the kernel source code from Motorola [here](https://github.com/MotorolaMobilityLLC/kernel-msm/releases/tag/MMI-S1RFS32.27-25-12), we can take a look at how this device node is used (heavily elided).
```c,name=drivers/soc/qcom/eud.c
static int msm_eud_probe(struct platform_device *pdev) {
...
   	chip->secure_eud_en = of_property_read_bool(pdev->dev.of_node, "qcom,secure-eud-en");
    if (chip->secure_eud_en && check_eud_mode_mgr2(chip))
		enable = 1;
	/* Proceed enable other EUD elements if bootloader has enabled it */
	if (msm_eud_hw_is_enabled(pdev)) {
		enable = EUD_ENABLE_CMD;
        ret = extcon_set_state_sync(chip->extcon, EXTCON_USB, true);
		ret = extcon_set_state_sync(chip->extcon, EXTCON_CHG_USB_SDP, true);
    }
...
}

static int msm_eud_hw_is_enabled(struct platform_device *pdev)
{
	struct eud_chip *chip = platform_get_drvdata(pdev);
	int sec_eud_enabled = 0;

	if (chip->secure_eud_en) {
		int ret = qcom_scm_io_readl(
				chip->eud_mode_mgr2_phys_base + EUD_REG_EUD_EN2,
				&sec_eud_enabled);
		return sec_eud_enabled;
	}

	return readl_relaxed(chip->eud_reg_base + EUD_REG_CSR_EUD_EN) & BIT(0);
}

static void enable_eud(struct platform_device *pdev)
{
	struct eud_chip *priv = platform_get_drvdata(pdev);
	int ret;

	/* write into CSR to enable EUD */
	writel_relaxed(BIT(0), priv->eud_reg_base + EUD_REG_CSR_EUD_EN);

	/* Enable secure eud if supported */
	if (priv->secure_eud_en && !check_eud_mode_mgr2(priv)) {
		ret = qcom_scm_io_writel(priv->eud_mode_mgr2_phys_base +
				   EUD_REG_EUD_EN2, EUD_ENABLE_CMD);
	}

	/*
	 * Set the default cable state to usb connect and charger
	 * enable
	 */
	extcon_set_state_sync(priv->extcon, EXTCON_USB, true);
	extcon_set_state_sync(priv->extcon, EXTCON_CHG_USB_SDP, true);

	dev_dbg(&pdev->dev, "%s: EUD is Enabled\n", __func__);
}
```

So, it looks like we have 2 different enable registers - one for EUD, and one for "secure EUD". 
The secure EUD enable register is written via the Secure Channel Manager (SCM), which eventually calls into the Qualcomm TEE.

# Comparison with the OnePlus 6
The Linaro blogpost mentions that even though EUD appears fused, it still works, suggesting that it's potentially enabled via a debug policy.

```c,name=Qualcomm_Technologies_Inc._SDM845_v1_SoC.dts
qcom,msm-eud@88e0000 {
	compatible = "qcom,msm-eud";
	interrupt-names = "eud_irq";
	interrupts = <0x00 0x1ec 0x04>;
	reg = <0x88e0000 0x2000>;
	reg-names = "eud_base";
	clocks = <0x20 0xa9>;
	clock-names = "cfg_ahb_clk";
	vdda33-supply = <0xb8>;
	status = "ok";
	phandle = <0x2ab>;
};
```

The OnePlus 6 device tree doesn't mention `secure-eud-en`, and they enable it simply by writing a 1 to `EUD_REG_CSR_EUD_EN` with `mw.l 0x88e1014 1`.
Let's give it a shot!

# Recompiling the kernel with dev/mem
The stock Moto G50 kernel doesn't include support for `/dev/mem`, so we need to recompile it. After following [Nathan Chance's Clang build instructions](https://github.com/nathanchance/android-kernel-clang),
downloading [AOSP clang prebuilts](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/),
and binutils from [AOSP GCC prebuilts](https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/) 
we can run the following:
```Bash
> cd kernel-msm-MMI-S1RFS32.27-25-12
# Extract the stock kernel config
> adb shell su -c "cat /proc/config.gz | gunzip > stock_moto_defconfig"
# Generate .config from our stock config
> PATH="clang-r383902/bin:aarch64-linux-android-4.9/bin:$PATH" ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android- MAKEFLAGS='O=out -j8 LLVM=1' make stock_moto_defconfig
```
and we get our kernel image: `out/arch/arm64/boot/Image: Linux kernel ARM64 boot executable Image, little-endian, 4K pages`.

Supposedly, you can directly pass this to `fastboot boot` and it should figure it out, but in my case, it just rebooted immediately after the Motorola boot logo.
Instead, we can just unpack, update, and repack the boot.img.

```Bash
> unpack_bootimg --boot_img boot.img --out out --format=mkbootimg | tee mkbootimg_args
> file out/kernel
out/kernel: Linux kernel ARM64 boot executable Image, little-endian, 4K pages
> cp kernel-msm-MMI-S1RFS32.27-25-12/out/arch/arm64/boot/Image out/kernel
> mkbootimg $(cat mkbootimg_args) --output repacked.img
> fastboot boot repacked.img
```

# Disappointment
Booted into AOSP recovery, we see some kernel logs about the feature:
```Bash
[    1.148174] msm-eud 1628000.qcom,msm-eud: TCSR qcom_scm_io_writel failed with rc:-22
[    1.148237] 1628000.qcom,msm-eud: ttyEUD0 at MMIO 0x0 (irq = 30, base_baud = 0) is a EUD UART
```

MMIO 0x0 doesn't seem like a good sign, but msm_eud_probe doesn't return an error if the TCSR (Top Control and Status Register, used for peripheral configuration) write fails.

Our `eud_reg_base` is 0x16280000 and EUD_REG_CSR_EUD_EN is 0x1014, but unfortunately we don't get what we're looking for:
```Bash
# devmem 0x16281014 4 1
--- one reboot later ---
# cat /sys/fs/pstore/console-ramoops-0  | tail -n2
[  374.069907] msm_watchdog f410000.qcom,wdt: Causing a QCOM Apps Watchdog bite!
[  374.077049] msm_watchdog f410000.qcom,wdt: Wdog - STS: 0xb0d52, CTL: 0x3, BARK TIME: 0x57fdf, BITE TIME: 0x6ffd6
```

So, unfortunately, it doesn't look like we are able to enable EUD on the Moto G50.
