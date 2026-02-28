# GPU Support in AI4All

AI4All supports both **NVIDIA (CUDA)** and **AMD (ROCm)** for hardware-accelerated inference.
GPU acceleration is typically 10–50× faster than CPU-only mode.

---

## Quick Start

```bash
bash setup.sh          # auto-detects your GPU
bash setup.sh --nvidia # force NVIDIA mode
bash setup.sh --amd    # force AMD mode
bash setup.sh --cpu    # disable GPU
```

---

## NVIDIA CUDA

### Requirements
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| GPU | GTX 1060 6 GB | RTX 3080 10 GB+ |
| Driver | 525+ | Latest |
| NVIDIA Container Toolkit | Required | — |

### Install Container Toolkit (Ubuntu/Debian)
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -sL https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=...] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
```

### Performance Notes
- **Flash Attention** auto-enabled on Ampere (RTX 30xx) and newer → 2–4× memory savings
- **Multi-GPU**: All GPUs used automatically (`count: all`)
- **Best quantization**: `Q4_K_M` (best quality/VRAM tradeoff)

---

## AMD ROCm

### Supported Architectures
| Architecture | GPUs | GFX Version |
|---|---|---|
| RDNA 3 | RX 7900/7800/7700/7600 | 11.0.0 – 11.0.2 |
| RDNA 2 | RX 6900/6800/6700 XT | 10.3.0 |
| RDNA 1 | RX 5700/5600 XT | 10.1.0 |
| CDNA 2 | MI210/MI250 | 9.0.10 |

### Install ROCm (Ubuntu)
```bash
wget https://repo.radeon.com/amdgpu-install/6.1.3/ubuntu/jammy/amdgpu-install_6.1.60103-1_all.deb
sudo dpkg -i amdgpu-install_6.1.60103-1_all.deb
sudo amdgpu-install --usecase=rocm --no-dkms
sudo usermod -aG render,video $USER && newgrp render
```

### Performance Notes
- `HSA_OVERRIDE_GFX_VERSION` is set automatically by `setup.sh`
- RDNA 2/3: `HSA_ENABLE_SDMA=0` improves stability (already set)
- ROCm LLM performance is ~70–90% of equivalent NVIDIA

---

## Model–VRAM Reference

| Model | Quantization | VRAM | Speed (RTX 4090) |
|---|---|---|---|
| phi3 (3.8B) | Q4_K_M | 3 GB | ~120 tok/s |
| llama3 (8B) | Q4_K_M | 5 GB | ~80 tok/s |
| codellama (13B) | Q4_K_M | 9 GB | ~50 tok/s |
| codellama (34B) | Q4_K_M | 20 GB | ~25 tok/s |
| llama3 (70B) | Q4_K_M | 40 GB | ~12 tok/s |

---

## Check GPU Status

```bash
curl http://localhost:8000/v1/gpu | python3 -m json.tool
```

The Web UI status bar shows: GPU backend · GPU name · VRAM
