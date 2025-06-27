#!/bin/bash
official_source="SM-S9210_HKTW_14_Opensource.zip" # change it with you downloaded file
build_root=$(pwd)
kernel_root="$build_root/kernel_source"
toolchains_root="$build_root/toolchains"
kernel_su_next_branch="v1.0.8"
susfs_branch="gki-android14-6.1"
container_name="sm8650-kernel-builder"

kernel_build_script="build_kernel_6.1.sh"
support_kernel="6.1" # only support 6.1 kernel
kernel_source_link="https://opensource.samsung.com/uploadSearch?searchValue=SM-S92"
kernel_toolchains_link="https://opensource.samsung.com/uploadSearch?searchValue=S24(Qualcomm)"

custom_config_name="pineapple_gki_defconfig"
custom_config_file="$kernel_root/arch/arm64/configs/$custom_config_name"

# Load utility functions
lib_file="$build_root/lib.sh"
if [ -f "$lib_file" ]; then
    source "$lib_file"
else
    echo "[-] Error: Library file not found: $lib_file"
    echo "[-] Please ensure lib.sh exists in the build directory"
    exit 1
fi

function clean() {
    rm -rf "$kernel_root"
}
function extract_toolchains() {
    echo "[+] Extracting toolchains..."
    if [ -d "$toolchains_root" ]; then
        echo "[+] Toolchains directory already exists. Skipping extraction."
        return 0
    fi
    local toolchains_file="toolchain.tar.gz"
    # extract the toolchains from the official source code
    echo "[+] toolchains not found. Extracting from $toolchains_file..."
    if [ ! -f "$toolchains_file" ]; then
        echo "Please download the official toolchians from Samsung Open Source Release Center."
        echo "link: $kernel_toolchains_link"
        exit 1
    fi
    mkdir -p "$toolchains_root"
    tar -xzf "$toolchains_file" -C "$toolchains_root" --strip-components=1
    if [ $? -ne 0 ]; then
        echo "[-] Failed to extract toolchains from $toolchains_file."
        rm -rf "$toolchains_root"
        exit 1
    fi
    echo "[+] Toolchains extracted successfully to $toolchains_root."
}
function prepare_source() {
    if [ ! -d "$kernel_root" ]; then
        # extract the official source code
        echo "[+] Extracting official source code..."
        if [ ! -f "Kernel.tar.gz" ]; then
            echo "[+] Kernel.tar.gz not found. Extracting from $official_source..."
            if [ ! -f "$official_source" ]; then
                echo "Please download the official source code from Samsung Open Source Release Center."
                echo "link: $kernel_source_link"
                exit 1
            fi
            unzip -o -q "$official_source" "Kernel.tar.gz"
        fi
        # extract the kernel source code
        local kernel_source_tar="Kernel.tar.gz"
        echo "[+] Extracting kernel source code..."
        mkdir -p "$kernel_root"
        tar -xzf "$kernel_source_tar" -C "$kernel_root" --strip-components=3 "./kernel_platform/common"
        if [ ! -d "$kernel_root" ]; then
            echo "Kernel source code not found. Please check the official source code."
            exit 1
        fi
        cd "$kernel_root"
        echo "[+] Checking kernel version..."
        local kernel_version=$(get_kernel_version)
        local kernel_kmi_version=$(echo $kernel_version | cut -d '.' -f 1-2)
        echo "[+] Kernel version: $kernel_version, KMI version: $kernel_kmi_version"
        if [ "$kernel_kmi_version" != "$support_kernel" ]; then
            echo "Kernel version is not $support_kernel. Please check the official source code."
            exit 1
        fi
        echo "[+] Setting up permissions..."
        chmod 777 -R "$kernel_root"
        echo "[+] Kernel source code extracted successfully."
    fi
}
function extract_kernel_config() {
    cd "$build_root"
    local tools_dir="$build_root/tools"
    if [ ! -d "$tools_dir" ]; then
        mkdir "$tools_dir"
    fi
    local kptools="$tools_dir/kptools-linux"
    # if kptools-linux not exists, download it
    if [ ! -f "$kptools" ]; then
        echo "kptools-linux not found, downloading..."
        wget https://github.com/bmax121/KernelPatch/releases/download/0.11.3/kptools-linux -O "$kptools"
        chmod +x "$kptools"
    fi
    if [ -f "boot.img.lz4" ]; then
        # use lz4 to decompress it
        lz4 -d -f boot.img.lz4 boot.img
    else
        if [ -f "boot.img" ]; then
            echo "boot.img already exists, skipping decompression."
        else
            echo "[-] boot.img not found."
            echo "[-] boot.img.lz4 not found, please put it in the current directory."
            echo "     Where to get boot.img?"
            echo "     - Downlaod the samsung firmware match your phone, extract it, and extract the boot.img.lz4 from the 'AP_...tar.md5'"
            exit 1
        fi
    fi
    echo "[+] boot.img decompressed successfully."
    # extract official kernel config from boot.img
    "$kptools" -i boot.img -f >boot.img.build.conf
    echo "[+] Kernel config extracted successfully."
    # see the kernel version of official kernel
    echo "[+] Kernel version of official kernel:"
    "$kptools" -i boot.img -d | head -n 3
    # copy the extracted kernel config to the kernel source and build using it
    echo "[+] Copying kernel config to the kernel source..."
    tail -n +2 boot.img.build.conf >"$custom_config_file"
    echo "[+] Kernel config updated successfully."
    echo "[+] Kernel config file: $custom_config_file"
    echo "[+] Copying stock boot.img to the kernel source..."
    local stock_boot_img="$kernel_root/stock"
    if [ ! -d "$stock_boot_img" ]; then
        mkdir "$stock_boot_img"
    fi
    cp boot.img "$stock_boot_img"
    if [ $? -ne 0 ]; then
        echo "[-] Failed to copy stock boot.img."
        exit 1
    fi
    echo "[+] Stock boot.img copied successfully."
    # https://github.com/ravindu644/Android-Kernel-Tutorials/?tab=readme-ov-file#02-fix-theres-an-internal-problem-with-your-device-issue
    cd "$kernel_root"
    echo "[+] Copy stock_config to kernel source..."
    tail -n +2 "$build_root/boot.img.build.conf" >"$kernel_root/arch/arm64/configs/stock_defconfig"
    echo "[+] Fix: 'There's an internal problem with your device.' issue."
    # $(obj)/config_data.gz: .*
    # $(obj)/config_data.gz: arch/arm64/configs/stock_defconfig FORCE
    sed -i 's/$(obj)\/config_data\.gz: .*/$(obj)\/config_data\.gz: arch\/arm64\/configs\/stock_defconfig FORCE/' "$kernel_root/kernel/Makefile"
}
function add_kernelsu_next() {
    echo "[+] Adding KernelSU Next..."
    cd "$kernel_root"
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s "$kernel_su_next_branch"
    cd "$build_root"
    echo "[+] KernelSU Next added successfully."
}
function __fix_patch() {
    cp "$build_root/kernel_patches/fix_patch.patch" "$kernel_root"
    echo "[+] Fixing patch..."
    cd "$kernel_root"
    patch -p1 -l <fix_patch.patch
    if [ $? -ne 0 ]; then
        echo "[-] Failed to apply fix patch."
        exit 1
    fi
    echo "[+] Fix patch applied successfully."
}
function __restore_fix_patch() {
    echo "[+] Restoring fix patch..."
    cp "$build_root/kernel_patches/fix_patch_reverse.patch" "$kernel_root"
    cd "$kernel_root"
    patch -p1 -l <fix_patch_reverse.patch
    if [ $? -ne 0 ]; then
        echo "[-] Failed to restore fix patch."
        exit 1
    fi
    echo "[+] Fix patch restored successfully."
}
function add_susfs() {
    local susfs_dir="$build_root/susfs"
    if [ ! -d "$susfs_dir" ]; then
        echo "[+] Cloning susfs4ksu repository..."
        git clone https://gitlab.com/simonpunk/susfs4ksu.git --depth 1 -b "$susfs_branch" "$susfs_dir"
    else
        echo "[+] Updating susfs4ksu repository..."
        cd "$susfs_dir"
        git fetch origin "$susfs_branch"
        git pull origin "$susfs_branch"
        cd "$build_root"
    fi
    if [ ! -d "$susfs_dir" ]; then
        echo "Failed to clone susfs4ksu repository."
        exit 1
    fi
    echo "[+] SuSFS4ksu repository cloned successfully."
    echo "[+] Copying SuSFS source code..."
    cp "$susfs_dir/kernel_patches/50_add_susfs_in_$susfs_branch.patch" "$kernel_root"
    if [ -d "$susfs_dir/kernel_patches/fs" ]; then
        cp -r "$susfs_dir/kernel_patches/fs/"* "$kernel_root/fs/"
    else
        echo "[-] Warning: $susfs_dir/kernel_patches/fs directory not found"
    fi

    if [ -d "$susfs_dir/kernel_patches/include" ]; then
        cp -r "$susfs_dir/kernel_patches/include/"* "$kernel_root/include/"
    else
        echo "[-] Warning: $susfs_dir/kernel_patches/include directory not found"
    fi
    echo "[+] Applying SuSFS patches..."
    cd "$kernel_root"
    __fix_patch # remove some samsung's changes, then susfs can be applied
    local patch_result=$(patch -p1 <50_add_susfs_in_$susfs_branch.patch)
    if [ $? -ne 0 ]; then
        echo "$patch_result"
        echo "[-] Failed to apply SuSFS patches."
        echo "$patch_result" | grep -q ".rej"
        exit 1
    else
        echo "[+] SuSFS patches applied successfully."
        echo "$patch_result" | grep -q ".rej"
    fi
    __restore_fix_patch # restore removed samsung's changes
    echo "[+] SuSFS added successfully."
    # 判断kernel_su_next_branch是否包含susfs
    if [[ "$kernel_su_next_branch" == *"susfs"* ]]; then
        echo "[+] SusFS is already included in KernelSU Next branch."
    else
        echo "[+] SusFS is not included in KernelSU Next branch, applying patch..."
        cd KernelSU-Next
        if ! _apply_patch "0001-kernel-implement-susfs-v1.5.8-KernelSU-Next-v1.0.8.patch"; then
            echo "[-] Failed to apply SuSFS integration patch"
            exit 1
        fi
        cd - >/dev/null
    fi
}
function fix_kernel_su_next_susfs() {
    echo "[+] Applying kernel config tweaks fix susfs with ksun..."
    _set_or_add_config CONFIG_KSU_SUSFS_SUS_SU n
    echo "[+] KernelSU Next with SuSFS fix applied successfully."
}
function apply_kernelsu_manual_hooks() {
    echo "[+] Applying syscall hooks..."
    cd "$kernel_root"
    if ! _apply_patch "wild_kernels/next/syscall_hooks.patch"; then
        echo "[-] Failed to apply syscall hooks patch"
        exit 1
    fi
    echo "[+] Syscall hooks applied successfully."
    cd - >/dev/null
    _set_or_add_config CONFIG_KSU_KPROBES_HOOK n
    _set_or_add_config CONFIG_KSU_WITH_KPROBES n
}
function apply_wild_kernels_config() {
    # Add additional tmpfs config setting
    _set_or_add_config CONFIG_TMPFS_XATTR y
    _set_or_add_config CONFIG_TMPFS_POSIX_ACL y

    # Add additional config setting
    _set_or_add_config CONFIG_IP_NF_TARGET_TTL y
    _set_or_add_config CONFIG_IP6_NF_TARGET_HL y
    _set_or_add_config CONFIG_IP6_NF_MATCH_HL y

    # Add BBR Config
    _set_or_add_config CONFIG_TCP_CONG_ADVANCED y
    _set_or_add_config CONFIG_TCP_CONG_BBR y
    _set_or_add_config CONFIG_NET_SCH_FQ y
    _set_or_add_config CONFIG_TCP_CONG_BIC n
    _set_or_add_config CONFIG_TCP_CONG_WESTWOOD n
    _set_or_add_config CONFIG_TCP_CONG_HTCP n
}
function apply_wild_kernels_fix() {
    echo "[+] Applying Wild Kernels fix..."
    cd "$kernel_root"

    local patches=(
        "wild_kernels/next/fix_apk_sign.c.patch"
        "wild_kernels/next/fix_core_hook.c.patch"
        "wild_kernels/next/fix_selinux.c.patch"
        "wild_kernels/next/fix_ksud.c.patch"
        "wild_kernels/next/manager.patch"
        "wild_kernels/69_hide_stuff.patch"
    )

    for patch in "${patches[@]}"; do
        if ! _apply_patch "$patch"; then
            echo "[-] Failed to apply wild kernels patch: $patch"
            exit 1
        fi
    done

    echo "[+] Wild Kernels fix applied successfully."
    cd - >/dev/null
}
function fix_driver_check() {
    # ref to: https://github.com/ravindu644/Android-Kernel-Tutorials/blob/main/patches/010.Disable-CRC-Checks.patch
    cd "$kernel_root"
    if ! _apply_patch "driver_fix.patch"; then
        echo "[-] Failed to apply driver fix patch"
        exit 1
    fi

    #Force Load Kernel Modules
    _set_or_add_config CONFIG_MODULES y
    _set_or_add_config CONFIG_MODULE_FORCE_LOAD y
    _set_or_add_config CONFIG_MODULE_UNLOAD y
    _set_or_add_config CONFIG_MODULE_FORCE_UNLOAD y
    _set_or_add_config CONFIG_MODVERSIONS y
    _set_or_add_config CONFIG_MODULE_SRCVERSION_ALL n
    _set_or_add_config CONFIG_MODULE_SIG n
    _set_or_add_config CONFIG_MODULE_COMPRESS n
    _set_or_add_config CONFIG_TRIM_UNUSED_KSYMS n

    echo "[+] Driver fix patch applied successfully."
}
function fix_samsung_securities() {
    # Disable Samsung Securities
    _set_or_add_config CONFIG_UH n
    _set_or_add_config CONFIG_UH_RKP n
    _set_or_add_config CONFIG_UH_LKMAUTH n
    _set_or_add_config CONFIG_UH_LKM_BLOCK n
    _set_or_add_config CONFIG_RKP_CFP_JOPP n
    _set_or_add_config CONFIG_RKP_CFP n
    _set_or_add_config CONFIG_SECURITY_DEFEX n
    _set_or_add_config CONFIG_PROCA n
    _set_or_add_config CONFIG_FIVE n
}
function add_build_script() {
    echo "[+] Adding build script..."
    cp "$build_root/$kernel_build_script" "$kernel_root/build.sh"
    sed -i "s/gki_defconfig/$custom_config_name/" "$kernel_root/build.sh"
    chmod +x "$kernel_root/build.sh"
    echo "[+] Build script added successfully."
}
function print_usage() {
    echo "Usage: $0 [container|clean|prepare]"
    echo "  container: Build the Docker container for kernel compilation"
    echo "  clean: Clean the kernel source directory"
    echo "  prepare: Prepare the kernel source directory"
    echo "  (default): Run the main build process"
}
function print_docker_usage() {
    echo "To build the kernel using Docker, run:"
    echo "docker run --rm -it -v \"$kernel_root:/workspace\" -v \"$toolchains_root:/toolchains\" $container_name /workspace/build.sh"
    echo ""
    echo "This will mount your current directory to /workspace in the container"
    echo "and run the build.sh script inside the container."
    echo ""
    echo "If you want to open a shell in the container for manual operations:"
    echo "docker run --rm -it -v \"$kernel_root:/workspace\" -v \"$toolchains_root:/toolchains\" $container_name /bin/bash"
}
function build_container() {
    echo "[+] Building Docker container for kernel compilation..."

    # Check if Docker is installed
    if ! command -v docker &>/dev/null; then
        echo "[-] Docker is not installed. Please install Docker first."
        echo "    Visit https://docs.docker.com/engine/install/ for installation instructions."
        return 1
    fi

    # Build Docker image from Dockerfile
    cd "$build_root"
    docker build -t $container_name .

    if [ $? -ne 0 ]; then
        echo "[-] Failed to build Docker image."
        return 1
    fi

    echo "[+] Docker image '$container_name' built successfully."
    echo "[+] You can now use the container to build the kernel."
    print_docker_usage

    return 0
}

function main() {
    echo "[+] Starting kernel build process..."

    # Validate environment before proceeding
    if ! validate_environment; then
        echo "[-] Environment validation failed"
        exit 1
    fi

    extract_toolchains
    clean
    prepare_source
    extract_kernel_config

    # Show configuration summary
    show_config_summary

    add_kernelsu_next
    add_susfs
    fix_kernel_su_next_susfs
    apply_kernelsu_manual_hooks
    apply_wild_kernels_config
    apply_wild_kernels_fix
    fix_driver_check
    fix_samsung_securities
    add_build_script

    echo "[+] All done. You can now build the kernel."
    echo "[+] Please 'cd $kernel_root'"
    echo "[+] Run the build script with ./build.sh"
    echo ""

    if docker images | grep -q "$container_name"; then
        print_docker_usage
    else
        echo "To build using Docker container instead:"
        echo "./build.sh container"
    fi
}

case "${1:-}" in
"container")
    build_container
    exit $?
    ;;
"clean")
    clean
    echo "[+] Cleaned kernel source directory."
    exit 0
    ;;
"prepare")
    prepare_source
    echo "[+] Prepared kernel source directory."
    exit 0
    ;;
"?" | "help" | "--help" | "-h")
    print_usage
    exit 0
    ;;
"kernel")
    main
    # build container if not exists
    if ! docker images | grep -q "$container_name"; then
        build_container
        if [ $? -ne 0 ]; then
            echo "[-] Failed to build Docker container."
            exit 1
        fi
    fi
    echo "[+] Building kernel using Docker container..."
    docker run --rm -it -v "$kernel_root:/workspace" -v "$toolchains_root:/toolchains" $container_name /workspace/build.sh

    exit 0
    ;;
"")
    main
    ;;
*)
    echo "[-] Unknown option: $1"
    print_usage
    exit 1
    ;;
esac
