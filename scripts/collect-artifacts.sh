#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/upstream/immortalwrt"
target_dir="$source_dir/bin/targets/starfive/generic"
artifact_dir="$repo_root/artifacts"

images=("$target_dir"/*visionfive2*v1.3b*sdcard.img.gz)
manifests=("$target_dir"/*.manifest)

if (( ${#images[@]} != 1 )); then
	echo "Expected exactly one VisionFive 2 v1.3B SD image, found ${#images[@]}." >&2
	exit 1
fi
if (( ${#manifests[@]} == 0 )); then
	echo 'No package manifest was produced.' >&2
	exit 1
fi
if [[ ! -f "$target_dir/sha256sums" ]]; then
	echo 'sha256sums was not produced.' >&2
	exit 1
fi

rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"
cp "${images[@]}" "$artifact_dir/"
cp "${manifests[@]}" "$artifact_dir/"
cp "$target_dir/sha256sums" "$artifact_dir/"
cp "$source_dir/.config" "$artifact_dir/.config"

if find "$artifact_dir" -maxdepth 1 -type f -name '*.img' -print -quit | grep -q .; then
	echo 'Refusing to stage an uncompressed disk image.' >&2
	exit 1
fi

printf '%s\n' "${images[0]}"
