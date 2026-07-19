#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <input-sdcard.img.gz> <output-sdcard.img.gz>" >&2
	exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/image-functions.sh"

image_require_commands gzip cp dd stat od truncate sgdisk parted readlink mktemp

input_image="$(readlink -f -- "$1")"
output_image="$(readlink -m -- "$2")"

if [[ ! -f "$input_image" || "$input_image" != *.img.gz ]]; then
	echo "Not a compressed SD-card image: $input_image" >&2
	exit 2
fi
if [[ "$input_image" == "$output_image" ]]; then
	echo 'Input and output paths must be different.' >&2
	exit 2
fi

mkdir -p -- "$(dirname -- "$output_image")"
work_dir="$(mktemp -d -t vf2-image-finalize.XXXXXXXX)"
output_tmp="$(mktemp "${output_image}.tmp.XXXXXXXX")"
trap 'rm -rf -- "$work_dir"; rm -f -- "$output_tmp"' EXIT
sparse_image="$work_dir/sdcard.img"

image_decompress_sparse "$input_image" "$sparse_image"
image_repair_gpt "$sparse_image" >&2
sgdisk -v "$sparse_image" >&2
parted --script "$sparse_image" unit MiB print >&2

gzip -n -6 -c -- "$sparse_image" > "$output_tmp"
mv -f -- "$output_tmp" "$output_image"

printf '%s\n' "$output_image"
