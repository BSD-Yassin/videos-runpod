#!/usr/bin/env bash
# Idempotent RunPod bootstrap: ComfyUI + MiniMax H3 (pruned) + H3-safe flags.
# Intended to run as the pod docker_start_cmd on a runpod/pytorch CUDA image.
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
COMFY_DIR="${COMFY_DIR:-${WORKSPACE}/ComfyUI}"
COMFY_REF="${COMFY_REF:-v0.37.0}"
HF_REPO="${HF_REPO:-Comfy-Org/MiniMax-H3}"
DOWNLOAD_MODELS="${DOWNLOAD_MODELS:-1}"
INSTALL_MANAGER="${INSTALL_MANAGER:-1}"
COMFY_PORT="${COMFY_PORT:-8188}"

log() { printf '[bootstrap] %s\n' "$*"; }

setup_ssh() {
  if [[ -n "${PUBLIC_KEY:-}" ]]; then
    mkdir -p /root/.ssh
    printf '%s\n' "${PUBLIC_KEY}" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    if command -v service >/dev/null 2>&1; then
      service ssh start || true
    elif command -v sshd >/dev/null 2>&1; then
      /usr/sbin/sshd || true
    fi
  fi
}

ensure_layout() {
  mkdir -p \
    "${COMFY_DIR}" \
    "${WORKSPACE}/outputs" \
    "${COMFY_DIR}/models/diffusion_models" \
    "${COMFY_DIR}/models/text_encoders" \
    "${COMFY_DIR}/models/vae" \
    "${COMFY_DIR}/models/loras" \
    "${COMFY_DIR}/custom_nodes" \
    "${COMFY_DIR}/input" \
    "${COMFY_DIR}/output"
}

install_comfyui() {
  if [[ ! -d "${COMFY_DIR}/.git" ]]; then
    log "cloning ComfyUI ${COMFY_REF}"
    rm -rf "${COMFY_DIR}"
    git clone --depth 1 --branch "${COMFY_REF}" https://github.com/comfyanonymous/ComfyUI.git "${COMFY_DIR}"
  else
    log "ComfyUI already present; fetching ${COMFY_REF}"
    git -C "${COMFY_DIR}" fetch --depth 1 origin "refs/tags/${COMFY_REF}:refs/tags/${COMFY_REF}" 2>/dev/null || true
    git -C "${COMFY_DIR}" checkout -q "${COMFY_REF}" || true
  fi

  # Keep image PyTorch/CUDA; install the rest of ComfyUI deps.
  # Do NOT use a bare ^torch filter — it also drops torchsde / torchdiffeq.
  local req="${COMFY_DIR}/requirements.txt"
  if [[ -f "${req}" ]]; then
    log "installing ComfyUI Python deps (excluding torch/torchvision/torchaudio only)"
    local -a pkgs=()
    local line pkg
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%%#*}"
      line="$(echo "${line}" | tr -d '[:space:]')"
      [[ -z "${line}" ]] && continue
      pkg="${line%%[=<>!]*}"
      case "${pkg}" in
        torch|torchvision|torchaudio) continue ;;
      esac
      pkgs+=("${line}")
    done < "${req}"
    if ((${#pkgs[@]} > 0)); then
      pip install --no-cache-dir "${pkgs[@]}"
    fi
    # Required by comfy.k_diffusion; ensure present even if requirements drift.
    pip install --no-cache-dir torchsde
  fi

  python - <<'PY'
import torch
assert torch.cuda.is_available(), "CUDA not available in this image"
print(f"torch={torch.__version__} cuda={torch.version.cuda} device={torch.cuda.get_device_name(0)}")
PY
}

install_manager() {
  if [[ "${INSTALL_MANAGER}" != "1" ]]; then
    return 0
  fi
  local mgr="${COMFY_DIR}/custom_nodes/ComfyUI-Manager"
  if [[ ! -d "${mgr}/.git" ]]; then
    log "installing ComfyUI-Manager"
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git "${mgr}"
  fi
  # Do not install ComfyUI-MiniMaxH3-Cache — known to break H3.
  rm -rf "${COMFY_DIR}/custom_nodes/ComfyUI-MiniMaxH3-Cache"
}

need_hf() {
  if ! command -v hf >/dev/null 2>&1 && ! command -v huggingface-cli >/dev/null 2>&1; then
    pip install --no-cache-dir "huggingface_hub[cli]"
  fi
}

hf_get() {
  local file="$1"
  if command -v hf >/dev/null 2>&1; then
    hf download "${HF_REPO}" "${file}" --local-dir "${COMFY_DIR}/models"
  else
    huggingface-cli download "${HF_REPO}" "${file}" --local-dir "${COMFY_DIR}/models"
  fi
}

download_models() {
  if [[ "${DOWNLOAD_MODELS}" != "1" ]]; then
    log "DOWNLOAD_MODELS!=1; skipping MiniMax H3 weights"
    return 0
  fi

  need_hf

  # Pruned INT8 stack (~45 GB) — fits A40 / A6000 with CPU offload.
  # All official ComfyUI turbo LoRAs (~2 GB each) from Comfy-Org/MiniMax-H3.
  local files=(
    diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors
    diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors
    text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
    vae/minimax_h3_video_vae_fp16.safetensors
    vae/minimax_h3_audio_vae_fp32.safetensors
    loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors
    loras/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors
    loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors
  )

  local f
  for f in "${files[@]}"; do
    if [[ -f "${COMFY_DIR}/models/${f}" ]]; then
      log "present: ${f}"
    else
      log "downloading: ${f}"
      hf_get "${f}"
    fi
  done
}

start_comfy() {
  export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

  # H3-safe defaults: disable pinned memory for 24 GB cards; do not use --lowvram.
  local -a flags=(
    --listen 0.0.0.0
    --port "${COMFY_PORT}"
    --disable-pinned-memory
  )

  if [[ -n "${COMFY_FLAGS:-}" ]]; then
    # shellcheck disable=SC2206
    flags+=(${COMFY_FLAGS})
  fi

  cd "${COMFY_DIR}"
  log "starting ComfyUI on :${COMFY_PORT} (${flags[*]})"
  exec python main.py "${flags[@]}"
}

main() {
  setup_ssh
  ensure_layout
  install_comfyui
  install_manager
  download_models
  start_comfy
}

main "$@"
