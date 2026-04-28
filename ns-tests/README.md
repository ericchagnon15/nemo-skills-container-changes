# Perlmutter smoke-test assets

This directory contains a minimal, repo-safe bundle for exercising the Perlmutter path documented in
`docs/basics/perlmutter.md`.

Contents:

- `cluster_configs/perlmutter.yaml`: starter Slurm config for Perlmutter with `runtime: podman-hpc`
- `env_vars.example`: template for the environment variables expected by the smoke test
- `test_api_perlmutter.sh`: minimal `ns generate` invocation against an external OpenAI-compatible endpoint
- `quick_bench.sh`: `ns eval` benchmark run on gsm8k (small math benchmark, ~1.3k examples)
- `quick_robust.sh`: `ns robust_eval` robustness run on gpqa across multiple prompt configurations and seeds
- `prompt_set_config.yaml`: prompt-set config required by `quick_robust.sh`

Recommended local workflow:

1. Copy `env_vars.example` to `env_vars`
2. Fill in the actual endpoint, API key, NERSC username, and account details
3. Adjust `cluster_configs/perlmutter.yaml` for your own Perlmutter workspace and image name
4. Run `bash ns-tests/test_api_perlmutter.sh`

Do not commit `env_vars` with real secrets.

## Running evaluation scripts

To run `quick_bench.sh` or `quick_robust.sh`, make sure `env_vars` is filled in (the scripts source
it for `OPENAI_BASE_URL` and `OPENAI_API_KEY`). Both scripts call `ns prepare_data` automatically
to download the benchmark data to `/workspace/ns-data` on Perlmutter. Adjust `MODEL_NAME` and
`--output_dir` inside each script as needed.

`ns robust_eval` submits one Slurm job per prompt variation, which can exceed the job-count limit
of the `debug` QOS. Use `qos: regular` (or another non-debug queue) in
`cluster_configs/perlmutter.yaml` when running `quick_robust.sh`.

Multi-job submission also opens many SSH connections in quick succession. Configure SSH connection
multiplexing as described in `docs/basics/perlmutter.md` to avoid NERSC rate-limiting your account.
