locals {
  bootstrap_script = file("${path.module}/../scripts/bootstrap.sh")

  ssh_public_key = trimspace(
    var.ssh_public_key != "" ? var.ssh_public_key : (
      var.ssh_public_key_file != "" && fileexists("${path.module}/${var.ssh_public_key_file}")
      ? file("${path.module}/${var.ssh_public_key_file}")
      : ""
    )
  )

  pod_env = merge(
    {
      DOWNLOAD_MODELS         = var.download_models ? "1" : "0"
      COMFY_REF               = var.comfy_ref
      INSTALL_MANAGER         = "1"
      WORKSPACE               = "/workspace"
      PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True"
    },
    local.ssh_public_key != "" ? { PUBLIC_KEY = local.ssh_public_key } : {},
    var.hf_token != "" ? { HF_TOKEN = var.hf_token, HUGGING_FACE_HUB_TOKEN = var.hf_token } : {},
    var.comfy_flags != "" ? { COMFY_FLAGS = var.comfy_flags } : {},
  )
}

# One-shot session: models + outputs live on ephemeral pod volume (no network volume / $5 gate).
resource "runpod_pod" "comfyui" {
  count = var.create_pod ? 1 : 0

  name       = var.pod_name
  image_name = var.image_name

  compute_type      = "GPU"
  gpu_count         = var.gpu_count
  gpu_type_ids      = var.gpu_type_ids
  gpu_type_priority = "availability"
  cloud_type        = var.cloud_type
  support_public_ip = true
  interruptible     = false
  min_ram_per_gpu   = var.min_ram_per_gpu

  # Prefer listed DCs when set; otherwise let RunPod place anywhere.
  data_center_ids = length(var.data_center_ids) > 0 ? var.data_center_ids : null

  volume_in_gb         = var.volume_in_gb
  volume_mount_path    = "/workspace"
  container_disk_in_gb = var.container_disk_in_gb

  ports = [
    "8188/http",
    "22/tcp",
  ]

  env = local.pod_env

  docker_start_cmd = [
    "bash",
    "-c",
    local.bootstrap_script,
  ]
}
