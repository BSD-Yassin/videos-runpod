variable "pod_name" {
  type        = string
  description = "Display name for the RunPod GPU pod."
  default     = "comfyui-minimax-h3"
}

variable "data_center_ids" {
  type        = list(string)
  description = "Optional preferred data centers (empty = any). Looser = better availability."
  default     = []
}

variable "image_name" {
  type        = string
  description = "RunPod PyTorch/CUDA container image."
  # Stable CUDA 12.8 + torch 2.7.1 (avoid broken torch 2.8.0 cu128 tags).
  default = "runpod/pytorch:1.0.2-cu1281-torch271-ubuntu2204"
}

variable "gpu_type_ids" {
  type        = list(string)
  description = "48GB+ GPUs under ~$2/hr. H3 R2V OOMs on 24GB (4090/3090) — those are excluded."
  default = [
    "NVIDIA A40",
    "NVIDIA RTX A6000",
    "NVIDIA RTX PRO 6000 Blackwell Max-Q Workstation Edition",
    "NVIDIA L40",
    "NVIDIA RTX 6000 Ada Generation",
    "NVIDIA L40S",
    "NVIDIA A100 80GB PCIe",
  ]
}

variable "gpu_count" {
  type        = number
  description = "Number of GPUs."
  default     = 1
}

variable "cloud_type" {
  type        = string
  description = "COMMUNITY (cheaper) or SECURE."
  default     = "COMMUNITY"

  validation {
    condition     = contains(["COMMUNITY", "SECURE"], var.cloud_type)
    error_message = "cloud_type must be COMMUNITY or SECURE."
  }
}

variable "min_ram_per_gpu" {
  type        = number
  description = "Minimum host RAM per GPU in GB (H3 R2V needs headroom beyond VRAM)."
  default     = 48
}

variable "volume_in_gb" {
  type        = number
  description = "Ephemeral pod volume at /workspace (models ~50 GB + outputs). Destroyed with the pod."
  default     = 100

  validation {
    condition     = var.volume_in_gb >= 80 && var.volume_in_gb <= 500
    error_message = "volume_in_gb must be between 80 and 500 for H3 one-shot sessions."
  }
}

variable "container_disk_in_gb" {
  type        = number
  description = "Ephemeral container disk size in GB (OS/image scratch)."
  default     = 30
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key injected via PUBLIC_KEY. Overrides ssh_public_key_file when set."
  default     = ""
  sensitive   = true
}

variable "ssh_public_key_file" {
  type        = string
  description = "Path to an SSH public key file (default: project keys/runpod_comfy.pub)."
  default     = "../keys/runpod_comfy.pub"
}

variable "hf_token" {
  type        = string
  description = "Hugging Face token for gated/rate-limited downloads (optional)."
  default     = ""
  sensitive   = true
}

variable "download_models" {
  type        = bool
  description = "If true, bootstrap downloads MiniMax H3 pruned weights on first start."
  default     = true
}

variable "comfy_ref" {
  type        = string
  description = "ComfyUI git tag/ref (>= 0.32 required for H3)."
  default     = "v0.37.0"
}

variable "comfy_flags" {
  type        = string
  description = "Extra ComfyUI CLI flags appended after H3-safe defaults."
  default     = ""
}

variable "create_pod" {
  type        = bool
  description = "If false, create nothing (placeholder for future volume-only flows)."
  default     = true
}
