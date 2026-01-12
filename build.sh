#!/bin/bash

# --- Support Models List ---
# Extracted for easy maintenance and "all" iteration
ALL_MODELS=(
    beyond0lte beyond0lteks beyond1lte beyond1lteks 
    beyond2lte beyond2lteks beyondx beyondxks 
    d1 d1xks d2s d2x d2xks
)

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
    -m, --model [value]    Specify the model code (or "all" to build every model)
    -k, --ksu [y/N]        Include KernelSU
    -s, --susfs [y/N]      Include SuSFS
EOF
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            MODEL_INPUT="$2"
            shift 2
            ;;
        --ksu|-k)
            KSU_OPTION="$2"
            shift 2
            ;;
        --susfs|-s)
            SUSFS_OPTION="$2"
            shift 2
            ;;
        *)
            unset_flags
            exit 1
            ;;
    esac
done

# Handle the "all" logic
if [[ "$MODEL_INPUT" == "all" ]]; then
    MODELS_TO_BUILD=("${ALL_MODELS[@]}")
else
    MODELS_TO_BUILD=("$MODEL_INPUT")
fi

echo "Preparing the build environment..."
pushd $(dirname "$0") > /dev/null
CORES=`cat /proc/cpuinfo | grep -c processor`

# --- Feature Selection (Prompt only once) ---
if [ -z "$KSU_OPTION" ]; then
    read -p "Include KernelSU (y/N): " KSU_OPTION
fi
if [ -z "$SUSFS_OPTION" ]; then
    read -p "Include SuSFS (y/N): " SUSFS_OPTION
fi

# --- Main Build Loop ---
for MODEL in "${MODELS_TO_BUILD[@]}"; do
    echo "==============================================="
    echo " STARTING BUILD FOR: $MODEL"
    echo "==============================================="

    # Reset variables for each loop iteration
    KSU=""
    N10=""
    SUSFS_VERSION=""

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

    # --- Model Configuration ---
    case $MODEL in
        beyond0lte)   BOARD=SRPRI28A016KU; SOC=exynos9820; TZDEV=new ;;
        beyond0lteks) BOARD=SRPRI28C007KU; SOC=exynos9820; TZDEV=new ;;
        beyond1lte)   BOARD=SRPRI28B016KU; SOC=exynos9820; TZDEV=new ;;
        beyond1lteks) BOARD=SRPRI28D007KU; SOC=exynos9820; TZDEV=new ;;
        beyond2lte)   BOARD=SRPRI17C016KU; SOC=exynos9820; TZDEV=new ;;
        beyond2lteks) BOARD=SRPRI28E007KU; SOC=exynos9820; TZDEV=new ;;
        beyondx)      BOARD=SRPSC04B014KU; SOC=exynos9820; TZDEV=new ;;
        beyondxks)    BOARD=SRPRK21D006KU; SOC=exynos9820; TZDEV=new ;;
        d1)           BOARD=SRPSD26B009KU; SOC=exynos9825; TZDEV=old ;;
        d1xks)        BOARD=SRPSD23A002KU; SOC=exynos9825; TZDEV=new ;;
        d2s)          BOARD=SRPSC14B009KU; SOC=exynos9825; TZDEV=old ;;
        d2x)          BOARD=SRPSC14C009KU; SOC=exynos9825; TZDEV=old ;;
        d2xks)        BOARD=SRPSD23C002KU; SOC=exynos9825; TZDEV=new ;;
        *) echo "Skipping unknown model: $MODEL"; continue ;;
    esac

    KERNEL_DEFCONFIG=extreme_"$MODEL"_defconfig
    DEFCONFIG_PATH="arch/arm64/configs/$KERNEL_DEFCONFIG"

    if [[ "$KSU_OPTION" == "y" ]]; then
        KSU=ksu.config
    fi

    # --- Inject SuSFS into Defconfig ---
    if [[ "$SUSFS_OPTION" == "y" ]]; then
        sed -i '/CONFIG_KSU_SUSFS/d' "$DEFCONFIG_PATH"
        cat << EOF >> "$DEFCONFIG_PATH"
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=n
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=n
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=n
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_SU=y
EOF
        SUSFS_HEADER="include/linux/susfs.h"
        if [ -f "$SUSFS_HEADER" ]; then
            SUSFS_VERSION=$(grep -E '^#define[[:space:]]+SUSFS_VERSION' "$SUSFS_HEADER" | awk '{print $3}' | tr -d '"')
        fi
    fi

    # Cleanup previous builds for this specific model
    rm -rf out
    rm -rf build/out/$MODEL
    mkdir -p build/out/$MODEL/zip/files
    mkdir -p build/out/$MODEL/zip/META-INF/com/google/android

    # TZDEV Switching logic
    if [ "$TZDEV" == "new" ] && [ ! -e "drivers/misc/tzdev/umem.c" ]; then
        echo "Switching to new TZDEV..."
        rm -rf drivers/misc/tzdev
        mkdir -p drivers/misc/tzdev
        cp -a build/tzdev/new/* drivers/misc/tzdev
    elif [ "$TZDEV" == "old" ] && [ -e "drivers/misc/tzdev/umem.c" ]; then
        echo "Switching to old TZDEV..."
        rm -rf drivers/misc/tzdev
        mkdir -p drivers/misc/tzdev
        cp -a build/tzdev/old/* drivers/misc/tzdev
    fi

    if [[ "$SOC" == "exynos9825" ]]; then
        N10=9825.config
    fi

    echo "Building kernel: $KERNEL_DEFCONFIG"
    make ${MAKE_ARGS} -j$CORES $KERNEL_DEFCONFIG extreme.config $KSU $N10 || abort
    make ${MAKE_ARGS} -j$CORES || abort

    # --- Image Creation ---
    cp out/arch/arm64/boot/Image build/out/$MODEL

    if [[ "$SOC" == "exynos9820" ]]; then
        ./toolchain/mkdtimg cfg_create build/out/$MODEL/dtb.img build/dtconfigs/exynos9820.cfg -d out/arch/arm64/boot/dts/exynos
    elif [[ "$SOC" == "exynos9825" ]]; then
        ./toolchain/mkdtimg cfg_create build/out/$MODEL/dtb.img build/dtconfigs/exynos9825.cfg -d out/arch/arm64/boot/dts/exynos
    fi

    ./toolchain/mkdtimg cfg_create build/out/$MODEL/dtbo.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung

    pushd build/ramdisk > /dev/null
    find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/$MODEL/ramdisk.cpio.gz || abort
    popd > /dev/null

    # mkbootimg execution
    ./toolchain/mkbootimg --base 0x10000000 --board $BOARD --cmdline 'loop.max_part=7' --hashtype sha1 \
    --header_version 1 --kernel build/out/$MODEL/Image --kernel_offset 0x00008000 \
    --os_patch_level 2024-08 --os_version 14.0.0 --pagesize 2048 \
    --ramdisk build/out/$MODEL/ramdisk.cpio.gz --ramdisk_offset 0xF0000000 --second_offset 0xF0000000 \
    --tags_offset 0x00000100 -o build/out/$MODEL/boot.img || abort

    # --- Packaging ---
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
    NAME="${version}_${MODEL}_UNOFFICIAL"
    [[ "$KSU_OPTION" == "y" ]] && NAME="${NAME}_KSU"
    [[ "$SUSFS_OPTION" == "y" ]] && NAME="${NAME}_SuSFS"
    NAME="${NAME}_${DATE}.zip"
    zip -r -qq ../"$NAME" .
    popd > /dev/null
    
    echo "Finished: $NAME"
done

popd > /dev/null
echo "All builds completed."
