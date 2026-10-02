output "pod_id" {
  description = "RunPod pod ID (empty if create_pod=false)."
  value       = try(runpod_pod.comfyui[0].id, null)
}

output "pod_desired_status" {
  description = "Expected pod status from the API."
  value       = try(runpod_pod.comfyui[0].desired_status, null)
}

output "cost_per_hr" {
  description = "Quoted cost in RunPod credits per hour."
  value       = try(runpod_pod.comfyui[0].cost_per_hr, null)
}

output "adjusted_cost_per_hr" {
  description = "Effective cost per hour after savings plans."
  value       = try(runpod_pod.comfyui[0].adjusted_cost_per_hr, null)
}

output "public_ip" {
  description = "Public IP when Community Cloud exposes one."
  value       = try(runpod_pod.comfyui[0].public_ip, null)
}

output "comfyui_proxy_url" {
  description = "RunPod HTTP proxy URL for ComfyUI (port 8188)."
  value = try(
    "https://${runpod_pod.comfyui[0].id}-8188.proxy.runpod.net",
    null
  )
}

output "ssh_hint" {
  description = "SSH via RunPod proxy using keys/runpod_comfy. Pull outputs before destroy."
  value = try(
    "ssh -i ../keys/runpod_comfy root@${runpod_pod.comfyui[0].id}-22.proxy.runpod.net",
    null
  )
}

output "outputs_pull_hint" {
  description = "Copy ComfyUI outputs locally before terraform destroy."
  value = try(
    "scp -i ../keys/runpod_comfy -r root@${runpod_pod.comfyui[0].id}-22.proxy.runpod.net:/workspace/ComfyUI/output ./localvideo/runpod-out",
    null
  )
}
