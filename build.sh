#!/bin/bash
SUSFS_REPO="https://github.com/ShirkNeko/susfs4ksu.git"

official_source="SM-S9210_HKTW_14_Opensource.zip" # change it with you downloaded file
build_root=$(pwd)
kernel_root="$build_root/kernel_source"
toolchains_root="$build_root/toolchains"
kernel_su_next_branch="v1.0.8"
susfs_branch="gki-android14-6.1"
container_name="sm8650-kernel-builder"

kernel_build_script="scripts/build_kernel_6.1.sh"
support_kernel="6.1" # only support 6.1 kernel
kernel_source_link="https://opensource.samsung.com/uploadSearch?searchValue=SM-S92"
kernel_toolchains_link="https://opensource.samsung.com/uploadSearch?searchValue=S24(Qualcomm)"

custom_config_name="pineapple_gki_defconfig"
custom_config_file="$kernel_root/arch/arm64/configs/$custom_config_name"

# Load utility functions
lib_file="$build_root/scripts/utils/lib.sh"
if [ -f "$lib_file" ]; then
    source "$lib_file"
else
    echo "[-] Error: Library file not found: $lib_file"
    echo "[-] Please ensure lib.sh exists in the build directory"
    exit 1
fi
core_file="$build_root/scripts/utils/core.sh"
if [ -f "$core_file" ]; then
    source "$core_file"
else
    echo "[-] Error: Core file not found: $core_file"
    echo "[-] Please ensure lib.sh exists in the build directory"
    exit 1
fi

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

function __fix_patch() {
    echo "[+] Fixing patch..."
    cd "$kernel_root"
    _apply_patch_strict "fix_patch.patch"
    if [ $? -ne 0 ]; then
        echo "[-] Failed to apply fix patch."
        exit 1
    fi
    echo "[+] Fix patch applied successfully."
}

function __restore_fix_patch() {
    echo "[+] Restoring fix patch..."
    cd "$kernel_root"
    _apply_patch_strict "fix_patch_reverse.patch"
    if [ $? -ne 0 ]; then
        echo "[-] Failed to restore fix patch."
        exit 1
    fi
    echo "[+] Fix patch restored successfully."
}

function add_susfs() {
    add_susfs_prepare
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
}

function print_usage() {
    echo "Usage: $0 [container|clean|prepare]"
    echo "  container: Build the Docker container for kernel compilation"
    echo "  clean: Clean the kernel source directory"
    echo "  prepare: Prepare the kernel source directory"
    echo "  (default): Run the main build process"
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

    show_config_summary

    add_kernelsu_next
    add_susfs
    fix_kernel_su_next_susfs
    apply_kernelsu_manual_hooks_for_next
    apply_wild_kernels_config
    apply_wild_kernels_fix_for_next
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
