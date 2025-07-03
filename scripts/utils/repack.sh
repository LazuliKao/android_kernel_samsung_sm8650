check_env() {
    # if [ -z "$KERNEL_ROOT" ]; then
    #     echo "[-] KERNEL_ROOT is not set. Please set it to the root of your kernel source."
    #     exit 1
    # fi
    # if [ ! -d "$KERNEL_ROOT" ]; then
    #     echo "[-] KERNEL_ROOT directory does not exist: $KERNEL_ROOT"
    #     exit 1
    # fi
}

prepare_magiskboot() {
    local tools_dir="./tools"
    local tools_bin_dir="$tools_dir/bin"
    local magiskboot="$tools_bin_dir/magiskboot"
    if [ ! -f "$magiskboot" ]; then
        echo "[-] magiskboot not found. Downloading..."
        if [ ! -d "$tools_dir" ]; then
            mkdir -p "$tools_dir"
        fi
        if [ ! -d "$tools_bin_dir" ]; then
            mkdir -p "$tools_bin_dir"
        fi
        local temp_dir="$tools_dir/temp"
        mkdir -p "$temp_dir"
        local magiskzip="$temp_dir/magisk.zip"
        wget https://github.com/topjohnwu/Magisk/releases/download/v29.0/Magisk-v29.0.apk -O "$magiskzip"
        local magiskzip_extracted_dir="$temp_dir/magisk_extracted"
        if [ ! -d "$magiskzip_extracted_dir" ]; then
            mkdir -p "$magiskzip_extracted_dir"
        fi
        local magiskboot_path="lib/x86_64/libmagiskboot.so"
        unzip -o "$magiskzip" "$magiskboot_path" -d "$magiskzip_extracted_dir"
        mv "$magiskzip_extracted_dir/$magiskboot_path" "$magiskboot"
        rm -rf "$temp_dir"
        chmod +x "$magiskboot"
    fi
    if [ ! -f "$magiskboot" ]; then
        echo "[-] Failed to prepare magiskboot. Please check your internet connection."
        exit 1
    fi
    echo "[+] magiskboot is ready: $magiskboot"
    export MAGISKBOOT_BIN=$(realpath $magiskboot)
}

repack_stock_img() {
    local stock_boot_img=$(realpath "$1")
    local new_kernel=$(realpath "$2")
    prepare_magiskboot
    local temp_unpack_dir="./tmp_unpack"
    mkdir -p "$temp_unpack_dir"
    pushd "$temp_unpack_dir" >/dev/null
    "$MAGISKBOOT_BIN" unpack "$stock_boot_img"
    if [ -f "kernel" ]; then
        echo "[+] Removing old kernel from boot.img..."
        rm -f kernel
    else
        echo "[-] No kernel found in boot.img to remove."
        exit 1
    fi
    if [ -f "$new_kernel" ]; then
        echo "[+] Copying new kernel to boot.img..."
        cp "$new_kernel" kernel
    else
        echo "[-] New kernel not found: $new_kernel"
        exit 1
    fi
    echo "[+] New kernel added to boot.img."
    # repack the boot.img
    echo "[+] Repacking boot.img..."
    if [ ! -d "../dist" ]; then
        mkdir -p ../dist
    fi
    cp "$new_kernel" ../dist/kernel
    local target_boot_img="../dist/boot.img"
    "$MAGISKBOOT_BIN" repack "$stock_boot_img" "$target_boot_img"
    echo "[+] Repacked boot.img: $(realpath "$target_boot_img")"
    echo "[+] file: $(file "$target_boot_img")"
    popd >/dev/null
    echo "[+] Repacked boot.img successfully. You can flash it using odin."
}

update_kernel_prop() {
    # anykernel.sh
    local kernel_name="$1"
    local device_names="$2"
    sed -i "s|^kernel.string=.*|kernel.string=$kernel_name|" anykernel.sh
    # remove device.name\d=.*
    sed -i "/^device.name[1-5]/d" anykernel.sh
    # add device.name\d=r0q before supported.versions=
    local idx=1
    for device_name in $(echo "$device_names" | tr ',' ' '); do
        sed -i "s|^supported.versions=|device.name${idx}=$device_name\\nsupported.versions=|" anykernel.sh
        idx=$((idx + 1))
    done
    sed -i "s|^BLOCK=.*|BLOCK=/dev/block/by-name/boot;|" anykernel.sh
    sed -i "s|^IS_SLOT_DEVICE=.*|IS_SLOT_DEVICE=auto;|" anykernel.sh
    # comment all line after dump_boot
    sed -i '/^dump_boot/,$ s/^/#/' anykernel.sh
    echo "split_boot;" >>anykernel.sh
    echo "flash_boot;" >>anykernel.sh
}

pack_anykernel() {
    local new_kernel=$(realpath "$1")
    local anykernel_dir="./AnyKernel3"
    if [ -d "$anykernel_dir" ]; then
        rm -rf "$anykernel_dir"
        echo "[+] Removed existing AnyKernel directory."
    fi
    if [ ! -d "$anykernel_dir" ]; then
        git clone https://github.com/osm0sis/AnyKernel3 "$anykernel_dir"
    fi
    pushd "$anykernel_dir" >/dev/null
    cp "$new_kernel" zImage
    update_kernel_prop
    local targetZip="../dist/AnyKernel.zip"
    if [ ! -d "../dist" ]; then
        mkdir -p ../dist
    fi
    if [ -f "$targetZip" ]; then
        rm -f "$targetZip"
        echo "[+] Removed existing AnyKernel.zip."
    fi
    zip -r9 "$targetZip" * -x "*.zip" "*.git*" "README.md"
    echo "[+] AnyKernel.zip created: $(realpath "$targetZip")"
    popd >/dev/null
}

# mkdir -p build && cd build
# repack_stock_img ../stock/boot.img ../out/arch/arm64/boot/Image
# pack_anykernel ../out/arch/arm64/boot/Image "r0q,r0p,r0x"

generate_info() {

}
susfs_version() {
    local SUSFS_VERSION=$(cat include/linux/susfs.h | grep -E '^#define SUSFS_VERSION' | cut -d' ' -f3 | sed 's/"//g')
    cd drivers/kernelsu
    local KSU_LOCAL_VERSION=$(git rev-list --count HEAD)
    local KSU_VERSION=$((10000 + $KSU_LOCAL_VERSION + 200))
    cd - >/dev/null
}
