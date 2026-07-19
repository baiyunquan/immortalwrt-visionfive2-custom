#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat >&2 <<'EOF'
Usage: expand-image.sh <input-sdcard.img.gz> <target-size|block-device> [output.img.gz]

Size examples:
  16GB   decimal SD-card capacity (16,000,000,000 bytes)
  16GiB  binary capacity (17,179,869,184 bytes)
  16000000000  exact byte count

A block device such as /dev/sdb may be supplied as the target. It is only read
to obtain its exact capacity; this script never writes to that device.
EOF
}

if (( $# < 2 || $# > 3 )); then
	usage
	exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/image-functions.sh"

image_require_commands gzip cp dd stat od truncate sgdisk parted losetup \
	e2fsck resize2fs blkid blockdev readlink mktemp awk sed

run_privileged() {
	if (( EUID == 0 )); then
		"$@"
	else
		if ! command -v sudo >/dev/null 2>&1; then
			echo "Root privileges are required for: $*" >&2
			return 1
		fi
		sudo "$@"
	fi
}

parse_size() {
	local value="${1^^}"
	local number suffix factor

	if [[ ! "$value" =~ ^([0-9]+)(B|K|KB|KI|KIB|M|MB|MI|MIB|G|GB|GI|GIB|T|TB|TI|TIB)?$ ]]; then
		echo "Invalid target size: $1" >&2
		return 1
	fi

	number="${BASH_REMATCH[1]}"
	suffix="${BASH_REMATCH[2]:-B}"
	case "$suffix" in
		B) factor=1 ;;
		K|KB) factor=1000 ;;
		KI|KIB) factor=1024 ;;
		M|MB) factor=1000000 ;;
		MI|MIB) factor=1048576 ;;
		G|GB) factor=1000000000 ;;
		GI|GIB) factor=1073741824 ;;
		T|TB) factor=1000000000000 ;;
		TI|TIB) factor=1099511627776 ;;
	esac

	if (( number > 9223372036854775807 / factor )); then
		echo "Target size is too large: $1" >&2
		return 1
	fi

	printf '%s\n' "$((number * factor))"
}

run_e2fsck() {
	local device="$1"
	local status

	set +e
	run_privileged e2fsck -f -y "$device"
	status=$?
	set -e

	if (( status > 1 )); then
		echo "e2fsck failed for $device with status $status" >&2
		return "$status"
	fi
}

input_image="$(readlink -f -- "$1")"
target_spec="$2"

if [[ ! -f "$input_image" || "$input_image" != *.img.gz ]]; then
	echo "Not a compressed SD-card image: $input_image" >&2
	exit 2
fi

if [[ -b "$target_spec" ]]; then
	target_bytes="$(run_privileged blockdev --getsize64 "$target_spec")"
	target_label="$(basename -- "$target_spec")"
else
	target_bytes="$(parse_size "$target_spec")"
	target_label="${target_spec//[^[:alnum:]._-]/_}"
fi
target_bytes=$(( target_bytes / 512 * 512 ))

if [[ -n "${3:-}" ]]; then
	output_image="$(readlink -m -- "$3")"
else
	output_image="${input_image%.img.gz}-${target_label}.img.gz"
fi
if [[ "$input_image" == "$output_image" ]]; then
	echo 'Input and output paths must be different.' >&2
	exit 2
fi

mkdir -p -- "$(dirname -- "$output_image")"
work_dir="$(mktemp -d -t vf2-image-expand.XXXXXXXX)"
output_tmp="$(mktemp "${output_image}.tmp.XXXXXXXX")"
loop_device=''

cleanup() {
	if [[ -n "$loop_device" ]]; then
		run_privileged losetup -d "$loop_device" >/dev/null 2>&1 || true
	fi
	rm -rf -- "$work_dir"
	rm -f -- "$output_tmp"
}
trap cleanup EXIT

sparse_image="$work_dir/sdcard.img"
image_decompress_sparse "$input_image" "$sparse_image"
image_repair_gpt "$sparse_image" >&2
base_bytes="$(stat -c '%s' "$sparse_image")"

if (( target_bytes <= base_bytes )); then
	echo "Target must exceed the normalized base image ($base_bytes bytes)." >&2
	exit 2
fi

mapfile -t root_partitions < <(
	parted -m "$sparse_image" unit s print | \
		awk -F: '$1 ~ /^[0-9]+$/ && tolower($6) == "rootfs" { print $1 }'
)
if (( ${#root_partitions[@]} != 1 )); then
	echo "Expected exactly one GPT partition named rootfs, found ${#root_partitions[@]}." >&2
	exit 1
fi
root_partition="${root_partitions[0]}"
root_start="$(sgdisk -i "$root_partition" "$sparse_image" | awk '$1 == "First" && $2 == "sector:" { print $3 }')"
if [[ ! "$root_start" =~ ^[0-9]+$ ]]; then
	echo 'Could not determine the rootfs start sector.' >&2
	exit 1
fi

while IFS=: read -r partition_number partition_start _; do
	partition_start="${partition_start%s}"
	if [[ "$partition_number" =~ ^[0-9]+$ ]] && (( partition_start > root_start )); then
		echo 'rootfs is not the final partition; refusing an unsafe resize.' >&2
		exit 1
	fi
done < <(parted -m "$sparse_image" unit s print)

truncate -s "$target_bytes" "$sparse_image"
image_repair_gpt "$sparse_image" >&2
last_usable="$(LC_ALL=C sgdisk -p "$sparse_image" | \
	sed -n 's/.*last usable sector is \([0-9][0-9]*\).*/\1/p')"
if [[ ! "$last_usable" =~ ^[0-9]+$ ]] || (( last_usable <= root_start )); then
	echo 'Could not calculate the final usable GPT sector.' >&2
	exit 1
fi

parted --script "$sparse_image" unit s resizepart "$root_partition" "${last_usable}s"

loop_device="$(run_privileged losetup --find --show --partscan "$sparse_image")"
if [[ "$loop_device" =~ [0-9]$ ]]; then
	root_device="${loop_device}p${root_partition}"
else
	root_device="${loop_device}${root_partition}"
fi

for _ in {1..50}; do
	[[ -b "$root_device" ]] && break
	sleep 0.1
done
if [[ ! -b "$root_device" ]]; then
	echo "Partition device did not appear: $root_device" >&2
	exit 1
fi

filesystem_type="$(run_privileged blkid -s TYPE -o value "$root_device")"
if [[ "$filesystem_type" != 'ext4' ]]; then
	echo "Expected ext4 on rootfs, found: ${filesystem_type:-unknown}" >&2
	exit 1
fi

run_e2fsck "$root_device"
run_privileged resize2fs "$root_device"
run_e2fsck "$root_device"
run_privileged losetup -d "$loop_device"
loop_device=''

sgdisk -v "$sparse_image"
parted --script "$sparse_image" unit MiB print

root_bytes=$(( (last_usable - root_start + 1) * 512 ))
echo "Target image: $target_bytes bytes ($((target_bytes / 512)) sectors)"
echo "rootfs: partition $root_partition, sectors $root_start-$last_usable ($root_bytes bytes)"

gzip -n -6 -c -- "$sparse_image" > "$output_tmp"
mv -f -- "$output_tmp" "$output_image"
printf 'Created %s\n' "$output_image"
