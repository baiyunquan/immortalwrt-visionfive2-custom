#!/usr/bin/env bash

# Shared helpers for VisionFive 2 disk images. This file is sourced by the
# executable scripts in this directory.

image_require_commands() {
	local missing=()
	local command_name

	for command_name in "$@"; do
		command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
	done

	if (( ${#missing[@]} > 0 )); then
		echo "Missing required commands: ${missing[*]}" >&2
		return 1
	fi
}

image_decompress_sparse() {
	local compressed_image="$1"
	local sparse_image="$2"

	gzip -t -- "$compressed_image"
	gzip -dc -- "$compressed_image" | cp --sparse=always /dev/stdin "$sparse_image"
}

image_repair_gpt() {
	local disk_image="$1"
	local current_bytes aligned_bytes alternate_lba declared_bytes target_bytes

	if [[ "$(dd if="$disk_image" bs=1 skip=512 count=8 status=none)" != 'EFI PART' ]]; then
		echo "No GPT header found in $disk_image" >&2
		return 1
	fi

	current_bytes="$(stat -c '%s' "$disk_image")"
	aligned_bytes=$(( (current_bytes + 511) / 512 * 512 ))
	alternate_lba="$(od -An -j 544 -N 8 -t u8 "$disk_image" | tr -d '[:space:]')"

	if [[ ! "$alternate_lba" =~ ^[0-9]+$ ]] || (( alternate_lba < 33 )); then
		echo "Invalid alternate GPT LBA in $disk_image: $alternate_lba" >&2
		return 1
	fi

	declared_bytes=$(( (alternate_lba + 1) * 512 ))
	if (( declared_bytes > current_bytes + 64 * 1024 * 1024 )); then
		echo 'GPT declares an implausibly large disk; refusing to create it.' >&2
		return 1
	fi

	target_bytes="$aligned_bytes"
	if (( declared_bytes > target_bytes )); then
		target_bytes="$declared_bytes"
	fi

	if (( target_bytes != current_bytes )); then
		truncate -s "$target_bytes" "$disk_image"
	fi

	# StarFive ptgen images omit the final 33-sector backup GPT area. Moving the
	# secondary header after padding reconstructs both its header and table.
	sgdisk -e "$disk_image"
}
