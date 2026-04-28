# Running NeMo-Skills on NERSC Perlmutter

This page documents the minimal path for running `nemo-skills` on NERSC Perlmutter from a Mac or other local workstation.

The supported workflow in this guide is:

- submit from a local machine through `ssh_tunnel`
- use `executor: slurm`
- use `runtime: podman-hpc`
- run a single-container job on Perlmutter
- connect to an external OpenAI-compatible API endpoint

This is the simplest supported Perlmutter path and is enough for commands such as:

- `ns run_cmd`
- `ns generate` against a pre-hosted API endpoint

## What changed in the repo

To make Perlmutter work, the Slurm path was extended with a `podman-hpc` runtime in addition to the existing Pyxis path.

The main behavior changes are:

- Slurm configs now accept `runtime: pyxis | podman-hpc`
- `runtime` defaults to `pyxis` if omitted
- `podman-hpc` jobs use `nemo_run.SlurmExecutor` in non-container mode and wrap the command with `podman-hpc run ...`
- `partition` is optional for Slurm configs, which is important on Perlmutter
- cluster configs can now carry default `account`, `qos`, and `constraint`
- if no timeout is configured, NeMo-Skills no longer submits the job with an implicit `100-00:00:00` walltime

## Implementation details by file

The Perlmutter support is not just documentation. The following code paths were changed so that
`nemo-skills` can submit a usable Phase 1 workload on NERSC.

### Runtime selection and config validation

- `nemo_skills/pipeline/utils/cluster.py`
  - defines `DEFAULT_SLURM_RUNTIME = "pyxis"` and `SUPPORTED_SLURM_RUNTIMES = ("pyxis", "podman-hpc")`
  - validates `runtime` whenever a cluster config is loaded
  - rejects `runtime` on non-Slurm executors
  - allows Slurm configs without `partition`
  - adds a helper that returns a Slurm timeout only when one was explicitly configured
- `nemo_skills/pipeline/utils/__init__.py`
  - re-exports the runtime helpers so the rest of the pipeline package can use them

### `ns setup` and example cluster config

- `nemo_skills/pipeline/setup.py`
  - prompts for the Slurm runtime during `ns setup`
  - keeps `pyxis` as the default so existing clusters continue to work
  - allows empty `partition`
  - collects optional `qos` and `constraint`
  - updates the generated config comments so the `containers:` section explains the difference between `pyxis` and `podman-hpc`
  - updates the timeout prompt so leaving it empty means "use cluster defaults unless `default_timeout` is set"
- `cluster_configs/example-slurm.yaml`
  - documents the new runtime field
  - clarifies that `account`, `qos`, and `constraint` can live in the cluster config
  - clarifies the container expectations for `pyxis` vs `podman-hpc`

### Slurm executor behavior

- `nemo_skills/pipeline/utils/exp.py`
  - detects whether a job uses the `podman-hpc` runtime
  - rejects unsupported Phase 1 workloads early
  - rejects `dockerfile:...` container specs for `podman-hpc`
  - wraps the final shell command in `podman-hpc run --rm ...`
  - mounts the requested paths into the `podman-hpc` container
  - forwards configured environment variables into the container
  - omits Pyxis-only `srun` flags when `runtime: podman-hpc`
  - passes `qos` and `constraint` through to `nemo_run.SlurmExecutor`
  - omits the `time` parameter entirely when no timeout was configured, so Slurm can use the site defaults
- `nemo_skills/pipeline/utils/declarative.py`
  - applies the same `podman-hpc` validation to declarative pipelines
  - wraps declarative inline commands with `podman-hpc run ...`
  - merges the cluster and per-command environment before wrapping the command

### Documentation and tests

- `docs/basics/index.md`
  - explains the difference between the `pyxis` and `podman-hpc` Slurm runtimes
  - explains that Perlmutter can use `account` / `qos` / `constraint` without a `partition`
  - documents the limited Phase 1 support model for `podman-hpc`
- `mkdocs.yml`
  - adds this Perlmutter page to the docs navigation
- `tests/test_configs.py`
  - covers default runtime selection, invalid runtime rejection, non-Slurm runtime rejection, and Slurm configs without `partition`
- `tests/test_declarative_pipeline.py`
  - verifies that unsupported multi-component declarative jobs are rejected for `podman-hpc`
- `tests/test_pipeline_utils.py`
  - verifies command wrapping for `podman-hpc`
  - verifies executor behavior differences between `pyxis` and `podman-hpc`
  - verifies `qos` / `constraint` handling
  - verifies that no timeout is sent to Slurm when none was configured
  - verifies rejection of `dockerfile:...` containers for `podman-hpc`

## Current limitations

`podman-hpc` support is currently Phase 1 support only.

The following are supported:

- single-container jobs
- API-backed generation
- `ns generate` with `--server_address`
- `ns run_cmd`

The following are not yet supported:

- self-hosted `vllm` or `trtllm` sidecars launched by `ns`
- sandbox sidecars
- heterogeneous multi-component jobs
- `dockerfile:...` container specs inside the Slurm config

For Perlmutter, use a prebuilt image name in `containers:` and do not rely on `.sqsh`.

## Authentication from a local machine

NERSC requires MFA. Do not put passwords or OTPs in the cluster config.

The recommended workflow is to use `sshproxy`, which gives you a temporary SSH certificate after MFA. After that, NeMo-Skills can reuse the SSH identity for packaging code, syncing files, and submitting jobs.

Example:

```bash
sshproxy -u <nersc_user> -a
ssh -i ~/.ssh/nersc <nersc_user>@perlmutter.nersc.gov
```

In the cluster config, point `ssh_tunnel.identity` at the certificate or key using an absolute local path.

```yaml
ssh_tunnel:
  identity: /Users/<local_user>/.ssh/nersc-cert.pub
```

If `identity` is omitted, the current tunnel implementation can still fall back to interactive authentication, but the `sshproxy` path is much more practical.

!!! note

    Use an absolute path for `ssh_tunnel.identity`. `~` is not expanded there.

### SSH connection multiplexing

NeMo-Skills opens one SSH connection per submitted job. For robustness evaluations or any run that submits many jobs in a short window, this can trigger NERSC's rate-limiting and temporarily lock out your account.

Add the following two stanzas to `~/.ssh/config` (replacing `<nersc_user>` and path values with your own):

```
Host perlmutter-mux
    HostName perlmutter.nersc.gov
    User <nersc_user>
    ControlMaster auto
    ControlPath ~/.ssh/cm_perlmutter
    ControlPersist 600
    ServerAliveInterval 60
    IdentityFile /Users/<local_user>/.ssh/nersc

Host perlmutter.nersc.gov
    User <nersc_user>
    ProxyCommand ssh -q -W %h:%p perlmutter-mux
    IdentityFile /Users/<local_user>/.ssh/nersc-cert.pub
```

The first stanza establishes the master connection and holds it open for 10 minutes. The second stanza routes every subsequent connection (including those made by NeMo-Skills) through that single tunnel, so NERSC only sees one authentication event for the entire job-submission burst.

Open the master connection once before submitting:

```bash
ssh perlmutter-mux true
```

## Build a minimal image on Perlmutter

For API-backed generation you do not need CUDA, vLLM, or a training image. A small Python image with the NeMo-Skills runtime dependencies is enough.

Build the image on Perlmutter itself. Do not build it on an Apple Silicon Mac and expect it to run on Perlmutter.

### 1. Prepare a build directory on Perlmutter

```bash
mkdir -p ~/ns-image-build
cd ~/ns-image-build
```

If you have access to the NERSC registry cache, log in first:

```bash
podman-hpc login registry.nersc.gov
```

### 2. Copy dependency files from the local repo

Only the dependencies need to be baked into the image. The current local code is still packaged and uploaded at submit time.

From your local machine:

```bash
mkdir -p /tmp/ns-image-build
cp /Users/<local_user>/Desktop/Skills/core/requirements.txt /tmp/ns-image-build/core.requirements.txt
cp /Users/<local_user>/Desktop/Skills/requirements/pipeline.txt /tmp/ns-image-build/pipeline.requirements.txt
scp -i ~/.ssh/nersc /tmp/ns-image-build/* <nersc_user>@perlmutter.nersc.gov:~/ns-image-build/
```

### 3. Create the `Containerfile`

On Perlmutter, save this as `~/ns-image-build/Containerfile`.

```dockerfile
FROM registry.nersc.gov/docker.io/library/python:3.11
# If you do not use the NERSC registry cache, replace the line above with:
# FROM docker.io/library/python:3.11

ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    build-essential \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY core.requirements.txt /tmp/core.requirements.txt
COPY pipeline.requirements.txt /tmp/pipeline.requirements.txt

RUN python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install -r /tmp/core.requirements.txt -r /tmp/pipeline.requirements.txt

WORKDIR /workspace
```

### 4. Build, test, and migrate the image

On Perlmutter:

```bash
cd ~/ns-image-build
podman-hpc build -t nemo-skills-api:0.1 .
podman-hpc run --rm --entrypoint= nemo-skills-api:0.1 bash -lc \
  'python -c "import nemo_run, typer, openai, litellm, hydra; print(\"image ok\")"'
podman-hpc migrate nemo-skills-api:0.1
```

After migration, the image name `nemo-skills-api:0.1` can be used in the cluster config.

## Create a Perlmutter cluster config

Save a config such as `cluster_configs/perlmutter.yaml` locally:

```yaml
executor: slurm
runtime: podman-hpc

ssh_tunnel:
  host: perlmutter.nersc.gov
  user: <nersc_user>
  identity: /Users/<local_user>/.ssh/nersc-cert.pub
  job_dir: /pscratch/sd/<first-letter>/<nersc_user>/nemo-run

containers:
  nemo-skills: nemo-skills-api:0.1

account: <nersc_account>
qos: <nersc_qos>
constraint: <nersc_constraint>
nodes: <nersc_nodes>
ntasks_per_node: <nersc_ntasks_per_node>
default_timeout: <nersc_time>

mounts:
  - /pscratch/sd/<first-letter>/<nersc_user>/ns-api-demo:/workspace

env_vars:
  - HF_HOME=/workspace/hf-cache
```

Important details:

- `partition` is intentionally omitted
- `account`, `qos`, and `constraint` live in the cluster config
- `mounts` must point to paths that exist on Perlmutter, not on the local machine
- the code is still packaged automatically under `/nemo_run/code`

## Prepare the remote workspace

Create the workspace on Perlmutter:

```bash
mkdir -p /pscratch/sd/<first-letter>/<nersc_user>/ns-api-demo/hf-cache
```

Place your `input.jsonl` and `prompt.yaml` into that directory so that they appear inside the job as:

- `/workspace/input.jsonl`
- `/workspace/prompt.yaml`

## Run the first API-backed generation

From the local machine, export the API settings before running `ns generate`.

```bash
export MODEL_NAME=nemotron-nano-3
export OPENAI_BASE_URL=<your_openai_compatible_endpoint>
export OPENAI_API_KEY=<your_token>
export NVIDIA_API_KEY="$OPENAI_API_KEY"
```

Then run:

```bash
ns generate \
  --cluster=perlmutter \
  --server_type=openai \
  --model="$MODEL_NAME" \
  --server_address="$OPENAI_BASE_URL" \
  --output_dir=/workspace/generation \
  --input_file=/workspace/input.jsonl \
  ++prompt_config=/workspace/prompt.yaml
```

NeMo-Skills automatically forwards common API environment variables from the local submission environment into the Slurm job.

## Run evaluation and robustness benchmarks

The `ns-tests/` directory includes two example scripts for running benchmarks on top of an API-backed endpoint.

### Standard evaluation (`ns eval`)

`ns-tests/quick_bench.sh` runs a full evaluation on the gsm8k math benchmark (~1.3k examples):

```bash
bash ns-tests/quick_bench.sh
```

It calls `ns prepare_data` to download the benchmark data to `/workspace/ns-data` on Perlmutter, then runs `ns eval`. Adjust `MODEL_NAME` and the `--output_dir` inside the script as needed.

### Robustness evaluation (`ns robust_eval`)

`ns-tests/quick_robust.sh` runs a robustness evaluation on gpqa using multiple prompt configurations and random seeds:

```bash
bash ns-tests/quick_robust.sh
```

`ns robust_eval` behaves like `ns eval` but requires an additional `--prompt_set_config` argument pointing at a YAML file that lists the prompt variants to evaluate. `ns-tests/prompt_set_config.yaml` is a ready-to-use example that covers gpqa with ten MCQ prompt variations.

!!! warning

    `ns robust_eval` submits an independent Slurm job for each prompt variation. With the example `prompt_set_config.yaml` (ten gpqa variations × 8 seeds = multiple jobs), this will exceed the job-count limit of the `debug` QOS. Before running the robustness script, change `qos` in `cluster_configs/perlmutter.yaml` to `regular` (or another non-debug queue).

Both scripts source `./env_vars` for `OPENAI_BASE_URL` and `OPENAI_API_KEY`.

## Why both `OPENAI_API_KEY` and `NVIDIA_API_KEY`?

The OpenAI-compatible client chooses the API key based on the endpoint hostname.

- if the base URL contains `api.nvidia.com`, it looks for `NVIDIA_API_KEY`
- otherwise it falls back to `OPENAI_API_KEY`

If you are using a non-OpenAI hostname with an OpenAI-compatible API, setting both variables to the same token is the safest option.

## Troubleshooting

### Slurm cost estimate is absurdly high

If NERSC reports a huge cost such as `2400 node hours`, the job is probably being submitted with a very large walltime.

This repo now avoids inventing a `100-day` timeout when the cluster config does not define one. If you still want an explicit small cap for lightweight jobs, add:

```yaml
default_timeout: "00:10:00"
```

### The job cannot find `input.jsonl` or `prompt.yaml`

Those files must exist on the mounted Perlmutter path, not just on the local machine.

### The job fails because the API key is missing

Make sure the key is exported in the local shell before launching `ns generate`. The forwarding happens from the local environment at submit time.

### `ssh_tunnel.identity` does not work

Use an absolute path, not `~`. If needed, remove `identity` temporarily and verify that interactive `Password+OTP` auth still works.

### I want to run the Slurm inference example from the general Getting Started page

The stock Slurm inference example launches a server sidecar. That is not part of the current Phase 1 `podman-hpc` support.

Use this Perlmutter path for:

- API-backed generation
- generation against an already-running external server

Do not use it yet for self-hosted `vllm` launched by `ns`.

## References

- [NERSC MFA and sshproxy](https://docs.nersc.gov/connect/mfa/)
- [NERSC podman-hpc tutorial](https://docs.nersc.gov/development/containers/podman-hpc/podman-beginner-tutorial/)
- [NERSC container registry and pull-through cache](https://docs.nersc.gov/development/containers/registry/)
