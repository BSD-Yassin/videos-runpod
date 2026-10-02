#!/usr/bin/env python3
"""Download all official MiniMax H3 ComfyUI turbo LoRAs on a live RunPod via SSH."""
from __future__ import annotations

import argparse
import base64
import re
import sys
import time

import paramiko

REMOTE_SH = r"""#!/usr/bin/env bash
set -euo pipefail
cd /workspace/ComfyUI/models
command -v hf >/dev/null 2>&1 || pip install -q "huggingface_hub[cli]"
for f in \
  loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors \
  loras/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors \
  loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors
do
  if [ -f "$f" ]; then
    echo "present: $f ($(du -h "$f" | cut -f1))"
  else
    echo "downloading: $f"
    hf download Comfy-Org/MiniMax-H3 "$f" --local-dir /workspace/ComfyUI/models
  fi
done
ls -lh /workspace/ComfyUI/models/loras/
echo '<<<LORAS_COMPLETE>>>'
"""


def read_until(chan: paramiko.Channel, patterns: list[str], timeout: float) -> str:
    buf = ""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            chunk = chan.recv(4096).decode("utf-8", "ignore")
            if chunk:
                sys.stdout.write(chunk)
                sys.stdout.flush()
                buf += chunk
                for p in patterns:
                    if re.search(p, buf):
                        return buf
        except Exception:
            time.sleep(0.2)
    raise TimeoutError(f"timeout waiting for {patterns}; tail={buf[-400:]!r}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="ssh.runpod.io")
    ap.add_argument("--user", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--timeout", type=int, default=1200)
    args = ap.parse_args()

    key = paramiko.Ed25519Key.from_private_key_file(args.key)
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        args.host,
        username=args.user,
        pkey=key,
        timeout=30,
        allow_agent=False,
        look_for_keys=False,
    )
    chan = client.invoke_shell(term="xterm", width=160, height=40)
    chan.settimeout(1.0)

    read_until(chan, [r"root@.*#\s*$"], timeout=60)

    b64 = base64.b64encode(REMOTE_SH.encode()).decode()
    # Write remote script without embedding the completion marker on the wire as plain text.
    chan.send(f"echo {b64} | base64 -d > /tmp/get_loras.sh && chmod +x /tmp/get_loras.sh && bash /tmp/get_loras.sh\n")

    read_until(chan, [r"<<<LORAS_COMPLETE>>>"], timeout=args.timeout)
    time.sleep(1)
    try:
        while chan.recv_ready():
            sys.stdout.write(chan.recv(4096).decode("utf-8", "ignore"))
            sys.stdout.flush()
    except Exception:
        pass
    chan.send("exit\n")
    time.sleep(1)
    client.close()
    print("\n[local] done", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
