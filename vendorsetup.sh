#!/bin/bash

[ -z "${ANDROID_BUILD_TOP}" ] && return

DEVICE_PATH="device/GM/GM9PRO_sprout"
PATCH_ROOT="${ANDROID_BUILD_TOP}/${DEVICE_PATH}/patches"

HOTSPOT_PATCH_NAME="0015-tethering-hotspot-fixes.patch"
CONNECTIVITY_REPO="packages/modules/Connectivity"
CONNECTIVITY_PATCH_DIR="${PATCH_ROOT}/${CONNECTIVITY_REPO}"
HOTSPOT_PATCH="${CONNECTIVITY_PATCH_DIR}/${HOTSPOT_PATCH_NAME}"

SKIPPED_PATCHES=()

patch_is_already_applied() {
    local repo_path="$1"
    local patch="$2"
    local strip="${3:-1}"

    git -C "${repo_path}" apply \
        "-p${strip}" \
        --reverse \
        --check \
        "${patch}" >/dev/null 2>&1
}

patch_only_creates_existing_files() {
    local repo_path="$1"
    local patch="$2"
    local strip="${3:-1}"
    local target
    local stripped_target
    local created_count=0
    local diff_count=0
    local previous_line=""

    diff_count="$(grep -c '^diff --git ' "${patch}" 2>/dev/null)"
    [ "${diff_count}" -gt 0 ] || return 1

    while IFS= read -r line; do
        if [ "${previous_line}" = "--- /dev/null" ]; then
            case "${line}" in
                "+++ b/"*)
                    target="${line#+++ b/}"

                    stripped_target="$(
                        printf '%s\n' "${target}" |
                            cut -d/ -f"$((strip + 1))"-
                    )"

                    [ -n "${stripped_target}" ] || return 1
                    [ -e "${repo_path}/${stripped_target}" ] || return 1

                    created_count=$((created_count + 1))
                    ;;
            esac
        fi

        previous_line="${line}"
    done < "${patch}"

    [ "${created_count}" -eq "${diff_count}" ]
}

record_skipped_patch() {
    local repo="$1"
    local patch_name="$2"
    local reason="$3"

    SKIPPED_PATCHES+=("${repo}: ${patch_name} (${reason})")
}

apply_mail_patch() {
    local repo="$1"
    local patch="$2"
    local repo_path="${ANDROID_BUILD_TOP}/${repo}"
    local patch_name
    local output
    local status

    patch_name="$(basename "${patch}")"

    echo "  -> ${patch_name}"

    if [ ! -d "${repo_path}" ]; then
        echo "     Target repository is missing, skipping."
        record_skipped_patch "${repo}" "${patch_name}" "repository missing"
        return 0
    fi

    if [ ! -f "${patch}" ]; then
        echo "     Patch file is missing, skipping."
        record_skipped_patch "${repo}" "${patch_name}" "patch missing"
        return 0
    fi

    if patch_is_already_applied "${repo_path}" "${patch}" 1; then
        echo "     Already applied, skipping."
        return 0
    fi

    if patch_only_creates_existing_files "${repo_path}" "${patch}" 1; then
        echo "     Files added by this patch already exist, skipping."
        return 0
    fi

    output="$(git -C "${repo_path}" am -3 "${patch}" 2>&1)"
    status=$?

    if [ "${status}" -eq 0 ]; then
        [ -n "${output}" ] && printf '%s\n' "${output}"
        echo "     Applied successfully."
        return 0
    fi

    git -C "${repo_path}" am --abort >/dev/null 2>&1 || true

    echo "     Patch is incompatible with the current source, skipping."
    record_skipped_patch "${repo}" "${patch_name}" "incompatible source"

    return 0
}

apply_patch_series() {
    local repo="$1"
    local patch_dir="${PATCH_ROOT}/${repo}"
    local patch

    [ -d "${patch_dir}" ] || return 0

    echo "Applying patches to ${repo}..."

    while IFS= read -r patch; do
        apply_mail_patch "${repo}" "${patch}"
    done < <(
        find "${patch_dir}" \
            -maxdepth 1 \
            -type f \
            -name "*.patch" |
            sort
    )
}

apply_plain_patch() {
    local repo="$1"
    local patch="$2"
    local strip="${3:-1}"
    local repo_path="${ANDROID_BUILD_TOP}/${repo}"
    local patch_name

    patch_name="$(basename "${patch}")"

    echo "  -> ${patch_name}"

    if [ ! -d "${repo_path}" ]; then
        echo "     Target repository is missing, skipping."
        record_skipped_patch "${repo}" "${patch_name}" "repository missing"
        return 0
    fi

    if [ ! -f "${patch}" ]; then
        echo "     Patch file is missing, skipping."
        record_skipped_patch "${repo}" "${patch_name}" "patch missing"
        return 0
    fi

    if patch_is_already_applied \
        "${repo_path}" \
        "${patch}" \
        "${strip}"; then
        echo "     Already applied, skipping."
        return 0
    fi

    if patch_only_creates_existing_files \
        "${repo_path}" \
        "${patch}" \
        "${strip}"; then
        echo "     Files added by this patch already exist, skipping."
        return 0
    fi

    if ! git -C "${repo_path}" apply \
        "-p${strip}" \
        --check \
        "${patch}" >/dev/null 2>&1; then
        echo "     Patch is incompatible with the current source, skipping."
        record_skipped_patch "${repo}" "${patch_name}" "incompatible source"
        return 0
    fi

    if ! git -C "${repo_path}" apply \
        "-p${strip}" \
        "${patch}"; then
        echo "     Failed to apply patch, skipping."
        record_skipped_patch "${repo}" "${patch_name}" "apply failed"
        return 0
    fi

    echo "     Applied successfully."
    return 0
}

apply_connectivity_patches() {
    local patch
    local patch_name

    [ -d "${CONNECTIVITY_PATCH_DIR}" ] || return 0

    echo "Applying patches to ${CONNECTIVITY_REPO}..."

    while IFS= read -r patch; do
        patch_name="$(basename "${patch}")"

        if [ "${patch_name}" = "${HOTSPOT_PATCH_NAME}" ]; then
            continue
        fi

        apply_mail_patch \
            "${CONNECTIVITY_REPO}" \
            "${patch}"
    done < <(
        find "${CONNECTIVITY_PATCH_DIR}" \
            -maxdepth 1 \
            -type f \
            -name "*.patch" |
            sort
    )

    # Patch paths:
    # a/packages/modules/Connectivity/Tethering/...
    # Strip a/packages/modules/Connectivity with -p4.
    apply_plain_patch \
        "${CONNECTIVITY_REPO}" \
        "${HOTSPOT_PATCH}" \
        4
}

apply_patch_series "frameworks/native"
apply_patch_series "hardware/interfaces"
apply_patch_series "kernel/configs"

apply_connectivity_patches

apply_patch_series "packages/modules/DnsResolver"
apply_patch_series "system/apex"
apply_patch_series "system/bpf"
apply_patch_series "system/core"
apply_patch_series "system/netd"
apply_patch_series "system/vold"

echo
echo "GM9 Pro source patch processing completed."

if [ "${#SKIPPED_PATCHES[@]}" -gt 0 ]; then
    echo
    echo "Skipped patches:"
    printf '  - %s\n' "${SKIPPED_PATCHES[@]}"
else
    echo "All patches were applied or already present."
fi