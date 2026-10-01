#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
exporter_dir="$repo_dir/Tools/RVMExport"
checkpoint="$exporter_dir/rvm_mobilenetv3.pth"
output="$repo_dir/Vendor/Models/rvm_mobilenetv3_640x360_s0.5_fp16.mlmodel"

if [[ ! -x "$exporter_dir/.venv/bin/python" ]]; then
    python3.9 -m venv "$exporter_dir/.venv"
    "$exporter_dir/.venv/bin/python" -m pip install \
        -r "$exporter_dir/requirements-apple-silicon.txt"
fi

if [[ ! -f "$checkpoint" ]]; then
    curl -L --fail \
        'https://github.com/PeterL1n/RobustVideoMatting/releases/download/v1.0.0/rvm_mobilenetv3.pth' \
        -o "$checkpoint"
fi

cd "$exporter_dir"
.venv/bin/python export_coreml.py \
    --model-variant mobilenetv3 \
    --checkpoint rvm_mobilenetv3.pth \
    --resolution 640 360 \
    --downsample-ratio 0.5 \
    --quantize-nbits 16 \
    --output "$output"

shasum -a 256 "$output"
