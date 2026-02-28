//! GPU detection and capability reporting for NVIDIA (CUDA) and AMD (ROCm).
//!
//! Tries to detect available GPUs via nvidia-smi and rocm-smi,
//! then reports capabilities back to the P2P network so the
//! routing layer can prefer GPU-enabled nodes for inference.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::process::Command;
use tracing::{debug, info, warn};

// ── Public types ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum GpuVendor {
    Nvidia,
    Amd,
    // Future: Intel XPU, Apple Metal (handled at Ollama level)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GpuDevice {
    pub vendor:    GpuVendor,
    pub index:     u32,
    pub name:      String,
    /// Total VRAM in MiB
    pub vram_mib:  u64,
    /// Free VRAM in MiB (at detection time)
    pub vram_free_mib: u64,
    /// Current utilization 0–100%
    pub utilization_pct: Option<u8>,
    /// Driver / ROCm version
    pub driver_version: String,
    /// CUDA compute capability (e.g. "8.6") – NVIDIA only
    pub compute_capability: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GpuInfo {
    pub devices:     Vec<GpuDevice>,
    pub backend:     GpuBackend,
    /// Recommended Ollama environment variables
    pub ollama_env:  Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum GpuBackend {
    /// No GPU – CPU-only inference
    None,
    /// NVIDIA CUDA
    Cuda,
    /// AMD ROCm
    Rocm,
    /// Multiple vendors present (use first capable)
    Mixed,
}

impl GpuInfo {
    /// Total VRAM across all devices in MiB
    pub fn total_vram_mib(&self) -> u64 {
        self.devices.iter().map(|d| d.vram_mib).sum()
    }

    /// Can this node run a model requiring `required_mib` VRAM?
    pub fn can_fit_model(&self, required_mib: u64) -> bool {
        // Best-case: all VRAM available on a single card
        self.devices.iter().any(|d| d.vram_free_mib >= required_mib)
    }

    pub fn is_gpu_available(&self) -> bool {
        self.backend != GpuBackend::None
    }
}

// ── Detection ──────────────────────────────────────────────────────────────

/// Detect all available GPUs. Never panics – returns empty info on failure.
pub fn detect() -> GpuInfo {
    let mut devices = Vec::new();

    // Try NVIDIA first
    match detect_nvidia() {
        Ok(mut nv) => {
            info!("NVIDIA GPU(s) detected: {}", nv.len());
            devices.append(&mut nv);
        }
        Err(e) => debug!("No NVIDIA GPUs: {e}"),
    }

    // Try AMD
    match detect_amd() {
        Ok(mut amd) => {
            info!("AMD GPU(s) detected: {}", amd.len());
            devices.append(&mut amd);
        }
        Err(e) => debug!("No AMD GPUs: {e}"),
    }

    let backend = match (
        devices.iter().any(|d| d.vendor == GpuVendor::Nvidia),
        devices.iter().any(|d| d.vendor == GpuVendor::Amd),
    ) {
        (true,  true)  => GpuBackend::Mixed,
        (true,  false) => GpuBackend::Cuda,
        (false, true)  => GpuBackend::Rocm,
        (false, false) => GpuBackend::None,
    };

    let ollama_env = build_ollama_env(&devices, &backend);

    if devices.is_empty() {
        warn!("No GPU detected – running in CPU-only mode (inference will be slow)");
    } else {
        for d in &devices {
            info!(
                vendor  = ?d.vendor,
                name    = %d.name,
                vram_gb = d.vram_mib / 1024,
                "GPU ready"
            );
        }
    }

    GpuInfo { devices, backend, ollama_env }
}

// ── NVIDIA via nvidia-smi ─────────────────────────────────────────────────

fn detect_nvidia() -> Result<Vec<GpuDevice>> {
    // Query: index, name, total-memory, free-memory, utilization, driver, compute-cap
    let output = Command::new("nvidia-smi")
        .args([
            "--query-gpu=index,name,memory.total,memory.free,utilization.gpu,driver_version,compute_cap",
            "--format=csv,noheader,nounits",
        ])
        .output()?;

    if !output.status.success() {
        anyhow::bail!("nvidia-smi exited with error");
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut devices = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.splitn(7, ',').map(str::trim).collect();
        if parts.len() < 7 { continue; }

        let index            = parts[0].parse().unwrap_or(0);
        let name             = parts[1].to_string();
        let vram_mib: u64    = parts[2].parse().unwrap_or(0);
        let vram_free: u64   = parts[3].parse().unwrap_or(0);
        let util: Option<u8> = parts[4].parse().ok();
        let driver           = parts[5].to_string();
        let compute_cap      = Some(parts[6].to_string());

        devices.push(GpuDevice {
            vendor: GpuVendor::Nvidia,
            index,
            name,
            vram_mib,
            vram_free_mib: vram_free,
            utilization_pct: util,
            driver_version: driver,
            compute_capability: compute_cap,
        });
    }

    if devices.is_empty() {
        anyhow::bail!("nvidia-smi returned no devices");
    }
    Ok(devices)
}

// ── AMD via rocm-smi ──────────────────────────────────────────────────────

fn detect_amd() -> Result<Vec<GpuDevice>> {
    // rocm-smi --showmeminfo vram --showuse --showdriverversion --csv
    let output = Command::new("rocm-smi")
        .args(["--showproductname", "--showmeminfo", "vram", "--showuse", "--csv"])
        .output()?;

    if !output.status.success() {
        anyhow::bail!("rocm-smi exited with error");
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    parse_rocm_csv(&stdout)
}

fn parse_rocm_csv(csv: &str) -> Result<Vec<GpuDevice>> {
    // ROCm CSV format varies by version; we do a best-effort parse.
    // Typical header: device,VRAM Total Memory (B),VRAM Total Used Memory (B),GPU use (%)
    let mut devices: Vec<GpuDevice> = Vec::new();
    let mut headers: Vec<String> = Vec::new();

    for (i, line) in csv.lines().enumerate() {
        let parts: Vec<&str> = line.splitn(20, ',').map(str::trim).collect();
        if i == 0 {
            headers = parts.iter().map(|s| s.to_lowercase()).collect();
            continue;
        }
        if parts.is_empty() || parts[0].starts_with('#') { continue; }

        let idx_of = |needle: &str| -> Option<usize> {
            headers.iter().position(|h| h.contains(needle))
        };

        let index: u32 = parts[0].trim_start_matches("card").parse().unwrap_or(devices.len() as u32);

        // VRAM in bytes → MiB
        let vram_total = idx_of("total memory")
            .and_then(|i| parts.get(i))
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(0) / (1024 * 1024);

        let vram_used = idx_of("used memory")
            .and_then(|i| parts.get(i))
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(0) / (1024 * 1024);

        let util = idx_of("gpu use")
            .and_then(|i| parts.get(i))
            .and_then(|v| v.trim_end_matches('%').parse::<u8>().ok());

        // Get driver version from separate call (best effort)
        let driver_version = rocm_driver_version().unwrap_or_else(|| "unknown".to_string());

        // Product name – try a separate query
        let name = rocm_product_name(index).unwrap_or_else(|| format!("AMD GPU {index}"));

        devices.push(GpuDevice {
            vendor: GpuVendor::Amd,
            index,
            name,
            vram_mib:       vram_total,
            vram_free_mib:  vram_total.saturating_sub(vram_used),
            utilization_pct: util,
            driver_version,
            compute_capability: None, // N/A for AMD
        });
    }

    if devices.is_empty() { anyhow::bail!("No AMD devices parsed"); }
    Ok(devices)
}

fn rocm_driver_version() -> Option<String> {
    let out = Command::new("rocm-smi").arg("--showdriverversion").output().ok()?;
    let s = String::from_utf8_lossy(&out.stdout);
    // Look for a line like "Driver version: 6.1.3"
    s.lines()
        .find(|l| l.to_lowercase().contains("driver version"))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim().to_string())
}

fn rocm_product_name(index: u32) -> Option<String> {
    let out = Command::new("rocm-smi")
        .args(["--device", &index.to_string(), "--showproductname"])
        .output().ok()?;
    let s = String::from_utf8_lossy(&out.stdout);
    s.lines()
        .find(|l| l.to_lowercase().contains("card series") || l.to_lowercase().contains("gpu"))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim().to_string())
}

// ── Ollama environment ─────────────────────────────────────────────────────

fn build_ollama_env(devices: &[GpuDevice], backend: &GpuBackend) -> Vec<(String, String)> {
    let mut env = Vec::new();

    match backend {
        GpuBackend::Cuda | GpuBackend::Mixed => {
            // Tell CUDA which GPUs to use (all NVIDIA ones)
            let ids: Vec<String> = devices.iter()
                .filter(|d| d.vendor == GpuVendor::Nvidia)
                .map(|d| d.index.to_string())
                .collect();
            env.push(("CUDA_VISIBLE_DEVICES".into(), ids.join(",")));
            env.push(("OLLAMA_CUDA".into(), "1".into()));

            // Flash attention – supported on Ampere (8.0+) and newer
            let supports_flash = devices.iter()
                .filter(|d| d.vendor == GpuVendor::Nvidia)
                .any(|d| {
                    d.compute_capability
                        .as_deref()
                        .and_then(|cc| cc.split('.').next())
                        .and_then(|major| major.parse::<u32>().ok())
                        .map(|major| major >= 8)
                        .unwrap_or(false)
                });
            if supports_flash {
                env.push(("OLLAMA_FLASH_ATTENTION".into(), "1".into()));
            }
        }
        GpuBackend::Rocm => {
            let ids: Vec<String> = devices.iter()
                .filter(|d| d.vendor == GpuVendor::Amd)
                .map(|d| d.index.to_string())
                .collect();
            env.push(("HIP_VISIBLE_DEVICES".into(), ids.join(",")));
            env.push(("ROCR_VISIBLE_DEVICES".into(), ids.join(",")));
            env.push(("HSA_OVERRIDE_GFX_VERSION".into(), detect_gfx_version(devices)));
        }
        GpuBackend::None => {
            // CPU-only: tell Ollama to skip GPU probing
            env.push(("OLLAMA_NUM_GPU".into(), "0".into()));
        }
    }

    // Always set: max number of parallel requests based on GPU count
    let gpu_count = devices.len().max(1);
    env.push(("OLLAMA_NUM_PARALLEL".into(), (gpu_count * 2).to_string()));

    // Keep models in memory between requests (avoid re-loading)
    env.push(("OLLAMA_KEEP_ALIVE".into(), "30m".into()));

    env
}

/// Try to detect the GFX version for AMD (needed for some consumer cards).
/// Falls back to "11.0.0" (RDNA3) if unknown.
fn detect_gfx_version(devices: &[GpuDevice]) -> String {
    // Try reading from /sys/class/drm
    if let Ok(entries) = std::fs::read_dir("/sys/class/drm") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if !name.starts_with("card") || name.contains('-') { continue; }
            let gfx_path = format!("/sys/class/drm/{}/device/gfx_version", name);
            if let Ok(v) = std::fs::read_to_string(&gfx_path) {
                return v.trim().to_string();
            }
        }
    }

    // Fallback: guess from GPU name
    for d in devices.iter().filter(|d| d.vendor == GpuVendor::Amd) {
        let name_lower = d.name.to_lowercase();
        if name_lower.contains("7900") || name_lower.contains("7800") || name_lower.contains("7700") {
            return "11.0.0".to_string(); // RDNA 3
        }
        if name_lower.contains("6900") || name_lower.contains("6800") || name_lower.contains("6700") {
            return "10.3.0".to_string(); // RDNA 2
        }
        if name_lower.contains("5700") || name_lower.contains("5600") {
            return "10.1.0".to_string(); // RDNA 1
        }
    }

    "11.0.0".to_string() // Safe default for modern AMD GPUs
}

// ── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gpu_info_can_fit_model() {
        let info = GpuInfo {
            devices: vec![GpuDevice {
                vendor: GpuVendor::Nvidia,
                index: 0,
                name: "RTX 4090".to_string(),
                vram_mib: 24576,
                vram_free_mib: 20000,
                utilization_pct: Some(0),
                driver_version: "545.0".to_string(),
                compute_capability: Some("8.9".to_string()),
            }],
            backend: GpuBackend::Cuda,
            ollama_env: vec![],
        };
        assert!(info.can_fit_model(16000));  // 16 GB model fits
        assert!(!info.can_fit_model(24000)); // 24 GB model doesn't fit (not enough free)
    }

    #[test]
    fn rocm_csv_parse_basic() {
        let csv = "device,VRAM Total Memory (B),VRAM Total Used Memory (B),GPU use (%)\n\
                   card0,17179869184,2147483648,15\n";
        let devices = parse_rocm_csv(csv).unwrap();
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].vram_mib, 16384); // 16 GB
        assert_eq!(devices[0].vram_free_mib, 14336); // 14 GB free
    }

    #[test]
    fn gfx_version_fallback() {
        let devices = vec![GpuDevice {
            vendor: GpuVendor::Amd,
            index: 0,
            name: "AMD Radeon RX 7900 XTX".to_string(),
            vram_mib: 24576,
            vram_free_mib: 24000,
            utilization_pct: None,
            driver_version: "6.1".to_string(),
            compute_capability: None,
        }];
        assert_eq!(detect_gfx_version(&devices), "11.0.0");
    }
}
