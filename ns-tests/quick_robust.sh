## full evaluation on gsm8k (small/easy math benchmark, ~1.3k examples)
## The usage is nearly identical to the standard ns eval, but includes an additional required argument prompt_set_config to specify the set of prompts per benchmark to evaluate on.
source ./env_vars

export MODEL_NAME="gpt-oss-120b-high"
export NEMO_SKILLS_DATA_DIR=/workspace/ns-data

ns prepare_data --cluster=perlmutter gpqa \
  --data_dir=$NEMO_SKILLS_DATA_DIR

# gpqa:2 uses 2 random seeds for each prompt configuration (variation)
# prompt_set_config.yaml specifies the set of prompts to evaluate on``

ns robust_eval \
  --config_dir=./cluster_configs \
  --cluster=perlmutter \
  --prompt_set_config=./prompt_set_config.yaml \
  --server_type=openai \
  --server_address="$OPENAI_BASE_URL" \
  --model="$MODEL_NAME" \
  --output_dir=/workspace/eval-gpqa_oss_120b_robust \
  --benchmarks=gpqa:8 \
  --num_jobs=1 \
  ++skip_filled=True\
  ++parse_reasoning=False \
  ++max_concurrent_requests=16



