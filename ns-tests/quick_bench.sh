## full evaluation on gsm8k (small/easy math benchmark, ~1.3k examples)
source ./env_vars

export MODEL_NAME="gpt-oss-120b-high"
export NEMO_SKILLS_DATA_DIR=/workspace/ns-data

ns prepare_data --cluster=perlmutter gsm8k \
  --data_dir=$NEMO_SKILLS_DATA_DIR
ns eval \
  --config_dir=./cluster_configs \
  --cluster=perlmutter \
  --server_type=openai \
  --server_address="$OPENAI_BASE_URL" \
  --model="$MODEL_NAME" \
  --output_dir=/workspace/eval-gsm8k_oss_120b_bis \
  --benchmarks=gsm8k:0 \
  --rerun_done \
  ++skip_filled=True\
  ++max_concurrent_requests=32\
  ++parse_reasoning=False

# If the endpoint starts returning inline gpt-oss channel tags in `generation`
# instead of separate reasoning/final fields, switch to:
# ++parse_reasoning=True \
# ++end_reasoning_string='<|start|>assistant<|channel|>final<|message|>'

