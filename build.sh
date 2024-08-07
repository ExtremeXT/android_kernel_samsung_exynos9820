#!/bin/bash

abort()
{
    cd -
    echo "-----------------------------------------------"
    echo "Kernel compilation failed! Exiting..."
    echo "-----------------------------------------------"
    exit -1
}

unset_flags()
{
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]    Specify the model code of the phone
    -k, --ksu [y/N]        Include KernelSU
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            MODEL="$2"
            shift 2
            ;;
        --ksu|-k)
            KSU_OPTION="$2"
            shift 2
            ;;
        *)\
            unset_flags
            exit 1
            ;;
    esac
done

echo "Preparing the build environment..."

pushd $(dirname "$0") > /dev/null
CORES=`cat /proc/cpuinfo | grep -c processor`

# Define toolchain variables
CLANG_DIR=$PWD/toolchain/clang-r416183b
PATH=$CLANG_DIR/bin:$CLANG_DIR/lib:$PATH

MAKE_ARGS="
ARCH=arm64 \
LLVM=1 \
LLVM_IAS=1 \
CC=clang \
READELF=$CLANG_DIR/bin/llvm-readelf \
O=out
"

# Define specific variables
KERNEL_DEFCONFIG=extreme_"$MODEL"_defconfig
case $MODEL in
beyond0lte)
    BOARD=SRPRI28A016KU
    SOC=exynos9820
    TZDEV=new
;;
beyond0lteks)
    BOARD=SRPRI28C007KU
    SOC=exynos9820
    TZDEV=new
;;
beyond1lte)
    BOARD=SRPRI28B016KU
    SOC=exynos9820
    TZDEV=new
;;
beyond1lteks)
    BOARD=SRPRI28D007KU
    SOC=exynos9820
    TZDEV=new
;;
beyond2lte)
    BOARD=SRPRI17C016KU
    SOC=exynos9820
    TZDEV=new
;;
beyond2lteks)
    BOARD=SRPRI28E007KU
    SOC=exynos9820
    TZDEV=new
;;
beyondx)
    BOARD=SRPSC04B014KU
    SOC=exynos9820
    TZDEV=new
;;
beyondxks)
    BOARD=SRPRK21D006KU
    SOC=exynos9820
    TZDEV=new
;;
d1)
    BOARD=SRPSD26B009KU
    SOC=exynos9825
    TZDEV=old
;;
d1xks)
    BOARD=SRPSD23A002KU
    SOC=exynos9825
    TZDEV=new
;;
d2s)
    BOARD=SRPSC14B009KU
    SOC=exynos9825
    TZDEV=old
;;
d2x)
    BOARD=SRPSC14C009KU
    SOC=exynos9825
    TZDEV=old
;;
d2xks)
    BOARD=SRPSD23C002KU
    SOC=exynos9825
    TZDEV=new
;;
*)
    unset_flags
    exit
esac

if [ -z $KSU_OPTION ]; then
    read -p "Include KernelSU (y/N): " KSU_OPTION
fi

if [[ "$KSU_OPTION" == "y" ]]; then
    KSU=ksu.config
fi

rm -rf arch/arm64/configs/temp_defconfig
rm -rf build/out/$MODEL
mkdir -p build/out/$MODEL/zip/files
mkdir -p build/out/$MODEL/zip/META-INF/com/google/android

# Build kernel image
echo "-----------------------------------------------"
echo "Defconfig: "$KERNEL_DEFCONFIG""
if [ -z "$KSU" ]; then
    echo "KSU: N"
else
    echo "KSU: $KSU"
fi

# International Note 10 models use older TZDEV driver
# Korean Note 10 models along with all S10 models (both INTL and KOR)
# use newer TZDEV
# So we will dynamically change it based on model
# ...Samsung...

# If model wants new TZDEV and current TZDEV is old, switch it
# New tzdev has an extra "umem.c" file, we check if it doesn't exist
if [ "$TZDEV" == "new" ] && [ ! -e "drivers/misc/tzdev/umem.c" ]; then
    echo "Switching to new TZDEV..."
    rm -rf drivers/misc/tzdev
    mkdir -p drivers/misc/tzdev
    cp -a build/tzdev/new/* drivers/misc/tzdev
fi

# If model wants old TZDEV and current TZDEV is old, switch it
# New tzdev has an extra "umem.c" file, we check if it exists
if [ "$TZDEV" == "old" ] && [ -e "drivers/misc/tzdev/umem.c" ]; then
    echo "Switching to old TZDEV..."
    rm -rf drivers/misc/tzdev
    mkdir -p drivers/misc/tzdev
    cp -a build/tzdev/old/* drivers/misc/tzdev
fi

if [ "$SOC" == "exynos9825" ] then
    9825=9825.config
fi

echo "-----------------------------------------------"
echo "Building kernel using "$KERNEL_DEFCONFIG""
echo "Generating configuration file..."
echo "-----------------------------------------------"
make ${MAKE_ARGS} -j$CORES $KERNEL_DEFCONFIG extreme.config $KSU $9825 || abort

echo "Building kernel..."
echo "-----------------------------------------------"
make ${MAKE_ARGS} -j$CORES || abort

# Define constant variables
KERNEL_PATH=build/out/$MODEL/Image
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0xF0000000
SECOND_OFFSET=0xF0000000
TAGS_OFFSET=0x00000100
BASE=0x10000000
CMDLINE='loop.max_part=7'
HASHTYPE=sha1
HEADER_VERSION=1
OS_PATCH_LEVEL=2024-08
OS_VERSION=14.0.0
PAGESIZE=2048
RAMDISK=build/out/$MODEL/ramdisk.cpio.gz
OUTPUT_FILE=build/out/$MODEL/boot.img

## Build auxiliary boot.img files
# Copy kernel to build
cp out/arch/arm64/boot/Image build/out/$MODEL

# Build dtb
if [[ "$SOC" == "exynos9820" ]]; then
    echo "Building common exynos9820 Device Tree Blob Image..."
    echo "-----------------------------------------------"
    ./toolchain/mkdtimg cfg_create build/out/$MODEL/dtb.img build/dtconfigs/exynos9820.cfg -d out/arch/arm64/boot/dts/exynos
fi

if [[ "$SOC" == "exynos9825" ]]; then
    echo "Building common exynos9825 Device Tree Blob Image..."
    echo "-----------------------------------------------"
    ./toolchain/mkdtimg cfg_create build/out/$MODEL/dtb.img build/dtconfigs/exynos9825.cfg -d out/arch/arm64/boot/dts/exynos
fi
echo "-----------------------------------------------"

# Build dtbo
echo "Building Device Tree Blob Output Image for "$MODEL"..."
echo "-----------------------------------------------"
./toolchain/mkdtimg cfg_create build/out/$MODEL/dtbo.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung
echo "-----------------------------------------------"

# Build ramdisk
echo "Building RAMDisk..."
echo "-----------------------------------------------"
# Exynos 9820 fstab: fstab.exynos9820
# Exynos 9825 fstab: fstab.exynos9825
# So we will rename it dynamically
if [ "$SOC" == "exynos9825" ] && [ ! -e "build/ramdisk/fstab.exynos9825" ]; then
    echo "Switching to 9825 fstab..."
    cp -a build/ramdisk/fstab.exynos9820 build/ramdisk/fstab.exynos9825
    rm -rf build/ramdisk/fstab.exynos9820
fi

if [ "$SOC" == "exynos9820" ] && [ ! -e "build/ramdisk/fstab.exynos9820" ]; then
    echo "Switching to 9820 fstab..."
    cp -a build/ramdisk/fstab.exynos9825 build/ramdisk/fstab.exynos9820
    rm -rf build/ramdisk/fstab.exynos9825
fi

pushd build/ramdisk > /dev/null
find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/$MODEL/ramdisk.cpio.gz || abort
popd > /dev/null
echo "-----------------------------------------------"

# Create boot image
echo "Creating boot image..."
echo "-----------------------------------------------"
./toolchain/mkbootimg --base $BASE --board $BOARD --cmdline "$CMDLINE" --hashtype $HASHTYPE \
--header_version $HEADER_VERSION --kernel $KERNEL_PATH --kernel_offset $KERNEL_OFFSET \
--os_patch_level $OS_PATCH_LEVEL --os_version $OS_VERSION --pagesize $PAGESIZE \
--ramdisk $RAMDISK --ramdisk_offset $RAMDISK_OFFSET --second_offset $SECOND_OFFSET \
--tags_offset $TAGS_OFFSET -o $OUTPUT_FILE || abort

# Build zip
echo "Building zip..."
echo "-----------------------------------------------"
cp build/out/$MODEL/boot.img build/out/$MODEL/zip/files/boot.img
cp build/out/$MODEL/dtb.img build/out/$MODEL/zip/files/dtb.img
cp build/out/$MODEL/dtbo.img build/out/$MODEL/zip/files/dtbo.img
cp build/update-binary build/out/$MODEL/zip/META-INF/com/google/android/update-binary
cp build/updater-script build/out/$MODEL/zip/META-INF/com/google/android/updater-script

if [ "$SOC" == "exynos9825" ]; then
    version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' arch/arm64/configs/9825.config | cut -d '"' -f 2)
else
    version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' arch/arm64/configs/extreme.config | cut -d '"' -f 2)
fi
version=${version:1}
pushd build/out/$MODEL/zip > /dev/null
DATE=`date +"%d-%m-%Y_%H-%M-%S"`    

if [[ "$KSU_OPTION" == "y" ]]; then
    NAME="$version"_"$MODEL"_UNOFFICIAL_KSU_"$DATE".zip
else
    NAME="$version"_"$MODEL"_UNOFFICIAL_"$DATE".zip
fi
zip -r -qq ../"$NAME" .
popd > /dev/null
popd > /dev/null

echo "Build finished successfully!"
