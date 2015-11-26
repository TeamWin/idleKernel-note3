#!/bin/bash
# idleKernel for Samsung Galaxy Note 3 build script by jcadduono
# This build script is for TeamWin Recovery Project only
# This build script builds all variants in /ik.ramdisk/variant/

################### BEFORE STARTING ################
#
# download a working toolchain and extract it somewhere and configure this file
# to point to the toolchain's root directory.
# I highly recommend Christopher83's Linaro GCC 4.9.x Cortex-A15 toolchain.
# Download it here: http://forum.xda-developers.com/showthread.php?t=2098133
#
# once you've set up the config section how you like it, you can simply run
# ./build_all.sh
# while inside the /idleKernel-note3/ directory.
#
###################### CONFIG ######################

# root directory of idleKernel git repo (default is this script's location)
RDIR=$(pwd)

[ -z $VER ] && \
# version number
VER=6.6

# version number of TWRP in ramdisk
TWRP_VER=2.8.7.0

# output directory of flashable recovery
OUT_DIR_ENFORCING="/home/jc/idlekernel.com/twrp/selinux_enforcing/v"$VER"_"$(date +'%Y_%m_%d')
OUT_DIR_PERMISSIVE="/home/jc/idlekernel.com/twrp/v"$VER"_"$(date +'%Y_%m_%d')

# should we make a TWRP flashable zip? (1 = yes, 0 = no)
MAKE_ZIP=1

# should we make an Odin flashable tar.md5? (1 = yes, 0 = no)
MAKE_TAR=1

# directory containing cross-compile arm-cortex_a15 toolchain
TOOLCHAIN=/home/jc/build/toolchain/arm-cortex_a15-linux-gnueabihf-linaro_4.9.4-2015.06

# amount of cpu threads to use in kernel make process
THREADS=5

SET_KERNEL_VERSION()
{
	# kernel version string appended to 3.4.x-idleKernel-hlte-
	# (shown in Settings -> About device)
	KERNEL_VERSION=$VARIANT-$VER-twrp

	# output filename of flashable recovery
	OUT_NAME=twrp-$TWRP_VER-idleKernel-$VER-hlte-$VARIANT
}

############## SCARY NO-TOUCHY STUFF ###############

export ARCH=arm
export CROSS_COMPILE=$TOOLCHAIN/bin/arm-eabi-

KDIR=$RDIR/build/arch/arm/boot

CLEAN_BUILD()
{
	echo "Cleaning build..."
	cd $RDIR
	rm -rf build
	echo "Removing old boot.img..."
	rm -f ik.zip/boot.img
	echo "Removing old zip/tar.md5 files..."
	rm -f $OUT_DIR/$OUT_NAME.zip
	rm -f $OUT_DIR/$OUT_NAME.tar.md5
}

BUILD_KERNEL()
{
	echo "Creating kernel config..."
	cd $RDIR
	mkdir -p build
	make -C $RDIR O=build ik_defconfig \
		VARIANT_DEFCONFIG=variant_hlte_$VARIANT \
		SELINUX_DEFCONFIG=selinux_$SELINUX
	echo "Starting build..."
	make -C $RDIR O=build -j"$THREADS"
}

BUILD_RAMDISK()
{
	echo "Building ramdisk structure..."
	cd $RDIR
	rm -rf build/ramdisk
	mkdir build/ramdisk
	cp -ar ik.ramdisk/common/* ik.ramdisk/variant/$VARIANT/* build/ramdisk
	cd $RDIR/build/ramdisk
	mkdir -pm 755 dev proc sys system/bin tmp vendor/lib
	mkdir -pm 771 data
	echo "Building ramdisk.img..."
	find | fakeroot cpio -o -H newc | xz --check=crc32 --lzma2=dict=2MiB > $KDIR/ramdisk.cpio.xz
	cd $RDIR
}

BUILD_BOOT_IMG()
{
	echo "Generating boot.img..."
	$RDIR/scripts/mkqcdtbootimg/mkqcdtbootimg --kernel $KDIR/zImage \
		--ramdisk $KDIR/ramdisk.cpio.xz \
		--dt_dir $KDIR \
		--cmdline "console=null androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x3F" \
		--base 0x00000000 \
		--pagesize 2048 \
		--ramdisk_offset 0x02000000 \
		--tags_offset 0x01E00000 \
		--output $RDIR/ik.zip/recovery.img
}

CREATE_ZIP()
{
	echo "Compressing to TWRP flashable zip file..."
	cd $RDIR/ik.zip
	zip -r -9 - * > $OUT_DIR/$OUT_NAME.zip
	cd $RDIR
}

CREATE_TAR()
{
	echo "Compressing to Odin flashable tar.md5 file..."
	cd $RDIR/ik.zip
	tar -H ustar -c recovery.img > $OUT_DIR/$OUT_NAME.tar
	cd $OUT_DIR
	md5sum -t $OUT_NAME.tar >> $OUT_NAME.tar
	mv $OUT_NAME.tar $OUT_NAME.tar.md5
	cd $RDIR
}

DO_BUILD()
{
	echo "Starting build for $OUT_NAME, SELINUX = $SELINUX..."
	CLEAN_BUILD && BUILD_KERNEL && BUILD_RAMDISK && BUILD_BOOT_IMG || {
		echo "Error!"
		exit -1
	}
	if [ $MAKE_ZIP -eq 1 ]; then CREATE_ZIP; fi
	if [ $MAKE_TAR -eq 1 ]; then CREATE_TAR; fi
}

#mkdir -p $OUT_DIR_ENFORCING
mkdir -p $OUT_DIR_PERMISSIVE

for V in $RDIR/ik.ramdisk/variant/*
do
	VARIANT=${V#$RDIR/ik.ramdisk/variant/}
	if ! [ -f $RDIR"/arch/arm/configs/variant_hlte_"$VARIANT ] ; then
		echo "Device variant/carrier $VARIANT not found in arm configs!"
		continue
	else
		SET_KERNEL_VERSION
		export LOCALVERSION=$KERNEL_VERSION
		#OUT_DIR=$OUT_DIR_ENFORCING
		#SELINUX="always_enforce"
		#DO_BUILD
		OUT_DIR=$OUT_DIR_PERMISSIVE
		SELINUX="never_enforce"
		DO_BUILD
	fi
done;

echo "Finished!"
