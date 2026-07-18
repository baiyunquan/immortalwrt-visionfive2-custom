#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "Usage: $0 <sdcard.img.gz>" >&2
	exit 2
fi

image="$(readlink -f -- "$1")"
if [[ ! -f "$image" || "$image" != *sdcard.img.gz ]]; then
	echo "Not a compressed SD-card image: $image" >&2
	exit 2
fi

gzip -t "$image"

validation_dir="$(mktemp -d -t vf2-image-validation.XXXXXXXX)"
trap 'rm -rf -- "$validation_dir"' EXIT
sparse_image="$validation_dir/sdcard.img"

# Preserve zero runs as holes so the temporary 12 GiB logical image consumes
# only the space needed by populated blocks.
gzip -dc -- "$image" | cp --sparse=always /dev/stdin "$sparse_image"

sgdisk -v "$sparse_image"
parted --script "$sparse_image" unit MiB print

echo 'Compressed image and GPT partition table checks passed.'
