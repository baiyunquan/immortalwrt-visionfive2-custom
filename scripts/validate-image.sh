#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 <sdcard.img.gz>" >&2
	exit 2
fi

image="$(readlink -f -- "$1")"
if [[ ! -f "$image" || "$image" != *.img.gz ]]; then
	echo "Not a compressed SD-card image: $image" >&2
	exit 2
fi

gzip -t "$image"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/image-functions.sh"
image_require_commands gzip cp stat sgdisk parted mktemp

validation_dir="$(mktemp -d -t vf2-image-validation.XXXXXXXX)"
trap 'rm -rf -- "$validation_dir"' EXIT
sparse_image="$validation_dir/sdcard.img"

image_decompress_sparse "$image" "$sparse_image"

image_bytes="$(stat -c '%s' "$sparse_image")"
if (( image_bytes % 512 != 0 )); then
	echo "Image size is not sector aligned: $image_bytes bytes" >&2
	exit 1
fi

sgdisk -v "$sparse_image"
parted --script "$sparse_image" unit MiB print

echo 'Compressed image and GPT partition table checks passed.'
