#!/bin/bash
official_source="SM-S9210_HKTW_14_Opensource.zip" # change it with you downloaded file
build_root=$(pwd)

container_name="sm8650-kernel-builder"

kernel_build_script="scripts/build_kernel_6.1.sh"
support_kernel="6.1" # only support 6.1 kernel
kernel_source_link="https://opensource.samsung.com/uploadSearch?searchValue=SM-S92"
kernel_toolchains_link="https://opensource.samsung.com/uploadSearch?searchValue=S24(Qualcomm)"

custom_config_name="pineapple_gki_defconfig"
source "$build_root/scripts/utils/config.sh"
_auto_load_config
source "$build_root/scripts/utils/lib.sh"
source "$build_root/scripts/utils/core.sh"

cache_root=$(realpath ${cache_root:-./cache})
config_hash=$(generate_config_hash)
source_hash=$(generate_source_hash)
cache_config_dir="$cache_root/config_${config_hash}"
cache_platform_dir="$cache_root/sm8650"
toolchains_root="$cache_platform_dir/toolchains"
kernel_root="$build_root/kernel_source_$source_hash"

function extract_toolchains() {
    echo "[+] Extracting toolchains..."
    if [ -d "$toolchains_root" ]; then
        echo "[+] Toolchains directory already exists. Skipping extraction."
        return 0
    fi
    try_extract_toolchains
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
    echo "Usage: $0 [container|clean|prepare|config]"
    echo "  container: Build the Docker container for kernel compilation"
    echo "  clean: Clean the kernel source directory"
    echo "  prepare: Prepare the kernel source directory"
    echo "  config: Show configuration properties and build.config file status"
    echo "  (default): Run the main build process"
    echo ""
    echo "Environment Variables:"
    echo "  CACHE_ROOT: Set custom cache directory for tools and toolchains"
    echo "              Default: $build_root/cache"
    echo "              Current: $cache_root"
    echo ""
    echo "Configuration File:"
    echo "  $CONFIG_FILE: Contains build configuration properties"
    echo "                Location: $build_root/$CONFIG_FILE"
    echo "                Use 'config' command to check status and properties"
    echo ""
    echo "Configuration-specific cache directory:"
    echo "  Based on KSU branch: $ksu_branch"
    echo "  Based on SuSFS branch: $susfs_branch"
    echo "  Cache subdirectory: $cache_config_dir"
}

function main() {
    echo "[+] Starting kernel build process..."
    echo "[+] Configuration: KSU=${ksu_branch}, SuSFS=${susfs_branch}"
    echo "[+] Cache directory: $cache_root"
    echo "[+] Shared toolchains: $toolchains_root"
    echo "[+] Configuration-specific cache: $cache_config_dir"

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

    add_kernelsu
    apply_kernelsu_manual_hooks
    if [ "$ksu_add_susfs" = true ]; then
        add_susfs
        fix_kernel_su_next_susfs
    fi
    [ "$ksu_platform" = "ksu-next" ] && apply_wild_kernels_fix_for_next
    apply_wild_kernels_config
    allow_disable_selinux
    change_kernel_name
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
"env" | "config")
    echo "[+] Build Configuration Status:"
    echo ""
    show_properties_info "$build_root/$CONFIG_FILE"
    echo ""
    if [ -f "$build_root/$CONFIG_FILE" ]; then
        list_properties "$build_root/$CONFIG_FILE"
    else
        echo "[*] Please create a config file."
    fi
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
    docker run --rm -i -v "$kernel_root:/workspace" -v "$toolchains_root:/toolchains" $container_name /workspace/build.sh
    if [ $? -ne 0 ]; then
        echo "[-] Kernel build failed."
        exit 1
    fi
    echo "[+] Kernel build completed successfully."
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
