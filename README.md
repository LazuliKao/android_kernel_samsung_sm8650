# Build Kernel For Samsung Galaxy S24 Series (Snapdragon)
- Test on: Ubuntu 24.04 LTS

```sh
# rm -rf kernel_platform &
env_root=$(pwd)
kernel_root="kernel_platform/common"


# ===Prepare===
# Downlaod from https://opensource.samsung.com/uploadSearch?searchValue=SM-S92
tar -zxf Kernel.tar.gz
cd $kernel_root
# Set up permissions for all files and directories
chmod 777 -R *
cd $env_root

# ===KernelSU Next===
cd $kernel_root
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next-susfs-dev
cd $env_root


# ===SuSFS===
branch="gki-android14-6.1"
# # if you use KernelSU, also apply the patch for KernelSU
# wget https://gitlab.com/simonpunk/susfs4ksu/-/raw/master/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch?ref_type=heads -O "$kernel_root/KernelSU-Next/10_enable_susfs_for_ksu.patch"
# cd $kernel_root/KernelSU
# patch -p1 < 10_enable_susfs_for_ksu.patch
# cd $env_root

# download the patches (maybe change to git clone later, hmm...)
wget https://gitlab.com/simonpunk/susfs4ksu/-/raw/$branch/kernel_patches/50_add_susfs_in_$branch.patch?ref_type=heads -O "$kernel_root/50_add_susfs_in_$branch.patch"

wget https://gitlab.com/simonpunk/susfs4ksu/-/raw/$branch/kernel_patches/fs/sus_su.c?ref_type=heads -O "$kernel_root/fs/sus_su.c"
wget https://gitlab.com/simonpunk/susfs4ksu/-/raw/$branch/kernel_patches/fs/susfs.c?ref_type=heads -O "$kernel_root/fs/susfs.c"
wget https://gitlab.com/simonpunk/susfs4ksu/-/raw/$branch/kernel_patches/include/linux/sus_su.h?ref_type=heads -O "$kernel_root/include/linux/sus_su.h"

wget https://gitlab.com/simonpunk/susfs4ksu/-/raw/$branch/kernel_patches/include/linux/susfs.h?ref_type=heads -O "$kernel_root/include/linux/susfs.h"
wget https://gitlab.com/simonpunk/susfs4ksu/-/raw/$branch/kernel_patches/include/linux/susfs_def.h?ref_type=heads -O "$kernel_root/include/linux/susfs_def.h"
# apply the patch
cd $kernel_root
patch -p1 < 50_add_susfs_in_$branch.patch
# read the output carefully, then you need to manually solve the conflicts if there are any reject files
cd $env_root

# ===Download Build Script===
wget https://github.com/ravindu644/Android-Kernel-Tutorials/raw/refs/heads/main/build_scripts/build_6.1.sh -O "$kernel_root/build.sh"
# may refer to other build scripts, edit it by your self, ref to https://github.com/fei-ke/android_kernel_samsung_sm8550/blob/kernelsu/build.sh

# ===Kernel Config===
# if kptools-linux not exists, download it
if [ ! -f ./kptools-linux ]; then
    echo "kptools-linux not found, downloading..."
    wget https://github.com/bmax121/KernelPatch/releases/latest/download/kptools-linux -O ./kptools-linux
    chmod +x ./kptools-linux
fi
# put official boot.img here
#     Where to get boot.img?
#     - Downlaod the samsung firmware match your phone, extract it, and extract the boot.img.lz4 from the `AP_...tar.md5`
# then use lz4 to decompress it
lz4 -d boot.img.lz4 boot.img
# extract official kernel config from boot.img
./kptools-linux -i boot.img -f > boot.img.build.conf
# see the kernel version of official kernel
./kptools-linux -i boot.img -d | head
# copy the extracted kernel config to the kernel source and build using it
tail -n +2 boot.img.build.conf > "$kernel_root/arch/arm64/configs/gki_defconfig"
# Disable Samsung Securities & Force Load Kernel Modules
#   otherwise you will get a bootloop phone
# ref to: https://github.com/ravindu644/Android-Kernel-Tutorials/tree/main/samsung-rkp
cat <<EOF >> "$kernel_root/arch/arm64/configs/gki_defconfig"

# Disable Samsung Securities
CONFIG_UH=n
CONFIG_UH_RKP=n
CONFIG_UH_LKMAUTH=n
CONFIG_UH_LKM_BLOCK=n
CONFIG_RKP_CFP_JOPP=n
CONFIG_RKP_CFP=n
CONFIG_SECURITY_DEFEX=n
CONFIG_PROCA=n
CONFIG_FIVE=n

#Force Load Kernel Modules
CONFIG_MODULES=y
CONFIG_MODULE_FORCE_LOAD=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_FORCE_UNLOAD=y
CONFIG_MODVERSIONS=y
CONFIG_MODULE_SRCVERSION_ALL=n
CONFIG_MODULE_SIG=n
CONFIG_MODULE_COMPRESS=n
CONFIG_TRIM_UNUSED_KSYMS=n

# fix ksun
CONFIG_KSU_SUSFS_SUS_SU=n
EOF

# ===Fix Other Issues===
# Fix Driver Issues
#   - Disable CRC Checks 
# ref to: https://github.com/ravindu644/Android-Kernel-Tutorials/blob/main/patches/010.Disable-CRC-Checks.patch
#   edit these files
#   - drivers/mmc/core/core.c
#   - kernel/module/version.c


# ===Build Kernel===
# have a look at current kernel version
echo "Kernel Version:"
make kernelversion
cd $kernel_root
# clean the kernel source
make clean
# run build script
./build.sh
```