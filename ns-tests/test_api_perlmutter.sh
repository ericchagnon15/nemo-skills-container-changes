#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/env_vars" ]]; then
  echo "Missing ${SCRIPT_DIR}/env_vars. Copy env_vars.example and fill in the required values." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/env_vars"

ns generate \
  --cluster=perlmutter \
  --cluster_config_dir="${SCRIPT_DIR}/cluster_configs" \
  --server_type=openai \
  --model="${MODEL_NAME}" \
  --server_address="${OPENAI_BASE_URL}" \
  --output_dir=/workspace/generation \
  --input_file=/workspace/input.jsonl \
  --rerun_done \
  ++prompt_config=/workspace/prompt.yaml
