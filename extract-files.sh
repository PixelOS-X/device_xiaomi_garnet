#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=garnet
VENDOR=xiaomi

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        system_ext/lib*/libwfdmmsrc_system.so)
            [ "$2" = "" ] && return 0
            grep -q "libgui_shim.so" "${2}" || "${PATCHELF}" --add-needed "libgui_shim.so" "${2}"
            ;;
        system_ext/lib64/libwfdnative.so)
            ${PATCHELF} --remove-needed "android.hidl.base@1.0.so" "${2}"
            grep -q "libinput_shim.so" "${2}" || "${PATCHELF}" --add-needed "libinput_shim.so" "${2}"
            ;;
        vendor/bin/hw/android.hardware.security.keymint-service-qti|vendor/lib/libqtikeymint.so|vendor/lib64/libqtikeymint.so)
            grep -q "android.hardware.security.rkp-V3-ndk.so" "${2}" || "${PATCHELF_0_17_2}" --add-needed "android.hardware.security.rkp-V3-ndk.so" "${2}"
            ;;
        vendor/etc/camera/pureView_parameter.xml)
            sed -i 's/=\([0-9]\+\)>/="\1">/g' "${2}"
            ;;
        vendor/etc/init/hw/init.batterysecret.rc|vendor/etc/init/hw/init.mi_thermald.rc|vendor/etc/init/hw/init.qti.kernel.rc)
            sed -i 's/on charger/on property:init.svc.vendor.charger=running/g' "${2}"
            ;;
        vendor/etc/media_codecs_parrot_v0.xml)
            sed -i -E '/media_codecs_(google_audio|google_c2|google_telephony|vendor_audio)/d' "${2}"
            ;;
        vendor/etc/seccomp_policy/atfwd@2.0.policy|vendor/etc/seccomp_policy/wfdhdcphalservice.policy|vendor/etc/seccomp_policy/sensors-qesdk.policy)
            [ -z "$2" ] || [ ! -f "$2" ] && return 0
            [ -n "$(tail -c 1 "${2}")" ] && echo >> "${2}"
            sed -i '/gettid: 1/d' "${2}"
            sed -i '/^[[:space:]]*$/d' "${2}"
            echo "gettid: 1" >> "${2}"
            ;;
        vendor/etc/seccomp_policy/c2audio.vendor.ext-arm64.policy)
            [ "$2" = "" ] && return 0
            grep -q "setsockopt: 1" "${2}" || echo "setsockopt: 1" >> "${2}"
            ;;       
        vendor/etc/vintf/manifest/c2_manifest_vendor.xml)
            sed -ni '/dolby/!p' "${2}"
            ;;
        vendor/lib64/vendor.libdpmframework.so)
            "${PATCHELF_0_17_2}" --add-needed "libhidlbase_shim.so" "${2}"
            ;;      
        vendor/lib64/libwvhidl.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --add-needed "libcrypto_shim.so" "${2}"
            ;;              
        vendor/bin/hw/vendor.dolby.hardware.dms@2.0-service)
            "${PATCHELF}" --add-needed "libstagefright_foundation-v33.so" "${2}"
            ;;
        vendor/lib64/hw/audio.primary.parrot.so)
            "${PATCHELF}" --replace-needed "libstagefright_foundation.so" "libstagefright_foundation-v33.so" "${2}"
            ;;
        vendor/lib/libstagefright_soft_ddpdec.so|vendor/lib/libstagefrightdolby.so|vendor/lib64/libdlbdsservice.so|vendor/lib64/libstagefright_soft_ddpdec.so|vendor/lib64/libstagefrightdolby.so)
            grep -q "libstagefright_foundation-v33.so" "${2}" || "${PATCHELF}" --replace-needed "libstagefright_foundation.so" "libstagefright_foundation-v33.so" "${2}"
            ;;        
    esac
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
