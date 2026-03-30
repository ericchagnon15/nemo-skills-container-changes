# Perlmutter smoke-test assets

This directory contains a minimal, repo-safe bundle for exercising the Perlmutter path documented in
`docs/basics/perlmutter.md`.

Contents:

- `cluster_configs/perlmutter.yaml`: starter Slurm config for Perlmutter with `runtime: podman-hpc`
- `env_vars.example`: template for the environment variables expected by the smoke test
- `test_api_perlmutter.sh`: minimal `ns generate` invocation against an external OpenAI-compatible endpoint

Recommended local workflow:

1. Copy `env_vars.example` to `env_vars`
2. Fill in the actual endpoint, API key, NERSC username, and account details
3. Adjust `cluster_configs/perlmutter.yaml` for your own Perlmutter workspace and image name
4. Run `bash ns-tests/test_api_perlmutter.sh`

Do not commit `env_vars` with real secrets.
