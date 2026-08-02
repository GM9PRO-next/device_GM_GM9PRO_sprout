#!/bin/bash

DEVICE_PATH="device/GM/GM9PRO_sprout"
PATCH_ROOT="${ANDROID_BUILD_TOP}/${DEVICE_PATH}/patches"

apply_patch_series() {
    local repo="$1"
    local patch_dir="${PATCH_ROOT}/${repo}"

    [ -d "${patch_dir}" ] || return 0

    echo "Applying patches to ${repo}..."

    while IFS= read -r patch; do
        echo "  -> $(basename "${patch}")"

        if git -C "${ANDROID_BUILD_TOP}/${repo}" apply \
            --reverse --check "${patch}" >/dev/null 2>&1; then
            echo "     Already applied, skipping"
            continue
        fi

        if ! git -C "${ANDROID_BUILD_TOP}/${repo}" am -3 "${patch}"; then
            echo "Failed to apply ${patch}"
            git -C "${ANDROID_BUILD_TOP}/${repo}" am --abort
            return 1
        fi
    done < <(find "${patch_dir}" -maxdepth 1 -type f -name '*.patch' | sort)
}

apply_plain_patch() {
    local patch="$1"

    echo "Applying plain patch: $(basename "${patch}")"

    if git -C "${ANDROID_BUILD_TOP}" apply \
        --reverse --check "${patch}" >/dev/null 2>&1; then
        echo "  Already applied, skipping"
        return 0
    fi

    if ! git -C "${ANDROID_BUILD_TOP}" apply \
        --check "${patch}" >/dev/null 2>&1; then
        echo "  ERROR: patch cannot be applied cleanly"
        return 1
    fi

    git -C "${ANDROID_BUILD_TOP}" apply "${patch}"
}

apply_patch_series "frameworks/native" || return 1
apply_patch_series "hardware/interfaces" || return 1
apply_patch_series "kernel/configs" || return 1

# Apply Connectivity mail patches except the manually applied hotspot patch.
CONNECTIVITY_PATCH_DIR="${PATCH_ROOT}/packages/modules/Connectivity"

if [ -d "${CONNECTIVITY_PATCH_DIR}" ]; then
    while IFS= read -r patch; do
        case "$(basename "${patch}")" in
            *tethering-hotspot-fixes.patch)
                continue
                ;;
        esac

        echo "Applying Connectivity patch: $(basename "${patch}")"

        if git -C "${ANDROID_BUILD_TOP}/packages/modules/Connectivity" apply \
            --reverse --check "${patch}" >/dev/null 2>&1; then
            echo "  Already applied, skipping"
            continue
        fi

        if ! git -C "${ANDROID_BUILD_TOP}/packages/modules/Connectivity" am -3 "${patch}"; then
            git -C "${ANDROID_BUILD_TOP}/packages/modules/Connectivity" am --abort
            return 1
        fi
    done < <(find "${CONNECTIVITY_PATCH_DIR}" -maxdepth 1 \
        -type f -name '*.patch' | sort)
fi

apply_plain_patch \
    "${CONNECTIVITY_PATCH_DIR}/0015-tethering-hotspot-fixes.patch" \
    || return 1

apply_patch_series "packages/modules/DnsResolver" || return 1
apply_patch_series "system/apex" || return 1
apply_patch_series "system/bpf" || return 1
apply_patch_series "system/core" || return 1
apply_patch_series "system/netd" || return 1
apply_patch_series "system/vold" || return 1

echo "GM9 Pro source patches applied successfully."
