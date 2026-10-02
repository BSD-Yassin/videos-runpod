# videos-runpod

Terraform deploy of a **RunPod GPU pod** for **ComfyUI** + local **MiniMax H3** video inference on **PyTorch/CUDA**, targeting **under $2/hr** on **48GB+ VRAM** (A40 / A6000 / L40 family). 24GB cards (4090/3090) are excluded — H3 R2V tends to OOM there.

## What you get

- Ephemeral **100 GB** pod volume at `/workspace` (models + a few outputs for one session)
- Pod on official RunPod PyTorch CUDA image
- Idempotent [`scripts/bootstrap.sh`](scripts/bootstrap.sh): ComfyUI ≥ 0.32, Manager, H3 models, VRAM-safe flags
- **No network volume** (avoids the $5 balance gate); destroy the pod when done — pull outputs first

## Cost target

| GPU | Cloud | Ballpark |
|-----|--------|----------|
| NVIDIA A40 (preferred) | Secure / Community | ~$0.35–0.49/hr |
| RTX A6000 / L40 / 6000 Ada | Secure | ~$0.53–0.84/hr |
| A100 80GB (last resort) | Secure | ~$1.59/hr |

All stay under $2/hr. Disk is billed with the pod while it runs.

## Licence note

MiniMax H3 open weights may restrict use in some regions (including EU / UK / KR / US). Confirm you are allowed to download and run them before setting `download_models = true`.

## Prerequisites

- RunPod API key ([console settings](https://www.runpod.io/console/user/settings))
- Optional: Hugging Face token (rate limits / gated downloads)
- Nix + direnv (project flake provides `terraform`, `jq`), or any Terraform ≥ 1.5 with the RunPod provider

## Local setup

```fish
cd /path/to/videos-runpod
direnv allow

# secrets in .envrc.local (gitignored), fish:
#   set -x RUNPOD_API_KEY 'your-runpod-api-key'
#   set -x HF_TOKEN 'your-hf-token'   # optional

# SSH key for the pod (gitignored under keys/)
mkdir -p keys
ssh-keygen -t ed25519 -f keys/runpod_comfy -N '' -C 'runpod-comfy'
```

Copy and edit variables:

```fish
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

## Deploy

```fish
cd terraform
terraform init
terraform plan
terraform apply -var="hf_token=$HF_TOKEN"
```

SSH uses `keys/runpod_comfy` (public half injected via `PUBLIC_KEY`):

```fish
ssh -i ../keys/runpod_comfy root@<pod_id>-22.proxy.runpod.net
```

Outputs include `comfyui_proxy_url` (e.g. `https://<pod_id>-8188.proxy.runpod.net`). If the HTTP proxy returns 403, tunnel instead:

```fish
ssh -i ../keys/runpod_comfy -L 8188:localhost:8188 root@<pod_id>-22.proxy.runpod.net
# then open http://127.0.0.1:8188
```

First boot downloads models (~45 GB) onto `/workspace` — that runs on the GPU clock. Generate, then **pull outputs before destroy**:

```fish
mkdir -p ../localvideo/runpod-out
scp -i ../keys/runpod_comfy -r root@<pod_id>-22.proxy.runpod.net:/workspace/ComfyUI/output ../localvideo/runpod-out
```

## Use ComfyUI

1. Open the proxy URL from terraform output (or the SSH tunnel)
2. `Workflow` → `Browse Templates` → `Video` → MiniMax H3
3. Prefer pruned INT8 / NVFP4 checkpoints already downloaded by bootstrap
4. Match turbo LoRA ↔ steps ↔ `shift_video=12` / `shift_audio=3` (prefer 8-step FL2V for cleaner audio)

## Tear down

```fish
# stop billing; models and unsaved outputs on the pod are gone
terraform destroy
```

## Host tweaks baked into bootstrap

- `--disable-pinned-memory` (safer for H3 offload on 48 GB hosts)
- `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`
- No `--lowvram` (conflicts with pinned-memory offload)
- Does **not** install `ComfyUI-MiniMaxH3-Cache` (breaks H3)

Override extras with `comfy_flags` in tfvars or env `COMFY_FLAGS` on the pod.

## Optional: download extra LoRAs on a live pod

[`scripts/download_loras_remote.py`](scripts/download_loras_remote.py) pulls all official ComfyUI turbo LoRAs over RunPod SSH (`ssh.runpod.io`). Bootstrap already includes them on new pods.
