# Intel Arrow Lake-H Linux Power Unlocker 🚀

[![Linux](https://img.shields.io/badge/Platform-Linux-orange.svg?logo=linux)](https://kernel.org)
[![Tested on Arch Linux](https://img.shields.io/badge/Tested%20On-Arch%20Linux-1793d1.svg?logo=archlinux)](https://archlinux.org)
[![Hardware](https://img.shields.io/badge/CPU-Intel%20Core%20Ultra%20200H-0071c5.svg?logo=intel)](https://intel.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> Fix for Intel Core Ultra (Arrow Lake-H / Core Ultra 200H series) laptops stuck at **~21W–22.4W** under load on Linux, unlocking full **62.6W sustained all-core boost (4.15 GHz)** matching Windows performance.

---

## ⚡ The Problem

On laptops powered by **Intel Core Ultra 200H (Arrow Lake-H)** processors (e.g., Core Ultra 5 225H on Lenovo IdeaPad / ThinkPad / Yoga / ASUS / Dell) running modern Linux kernels:
* Under multi-core loads, sustained and burst package power (`PkgWatt`) is hard-capped at **~21W–22.4W** (with core power `CorWatt` locked at ~18.2W).
* All-core frequencies remain pinned around **2.7–2.85 GHz**, even though CPU thermals remain very cool (60°C–63°C).
* On Windows, the exact same hardware, BIOS, and charger boost and sustain up to **62W+** at **4.1+ GHz**.

---

## 🔍 Root Cause Analysis

Inspecting silicon throttle registers via **`MSR 0x64f` (`MSR_CORE_PERF_LIMIT_REASONS`)** under load reveals:

```
0x1d001100
```

* **Status Bit 8 (`0x0100`)**: Max Turbo Ratio Limit active.
* **Status Bit 12 (`0x1000`)**: **Electrical Design Point (EDP) / Current Limit (IccMax) active**.
* **Status Bit 10 (`0x0400`)**: Package PL1/PL2 was **0** (RAPL power limits were not the active blocker).

### Why the 22W Clamp Happens:

1. **`MSR 0x601` (`MSR_VR_CURRENT_CONFIG`) & `intel_rapl_msr`**:
   The Linux kernel's RAPL driver registers `MSR 0x601` as RAPL **`constraint_2` (`peak_power` / Power Limit 4)**. On boot, the kernel initializes this constraint to **`64000000` µW (64W)**, setting `MSR 0x601` to `0x200` (512 in decimal).
   On Arrow Lake-H, `MSR 0x601` controls the Voltage Regulator peak current delivery (`IccMax`). Restricting it to `0x200` imposes a low ~64A threshold. Instantaneous microsecond current spikes during multi-core workloads collide with this limit, asserting Bit 12 (EDP/IccMax) and throttling clocks to **2.85 GHz (~22W)**.

2. **`intel-rapl:1` (`psys` - Platform System Power)**:
   The platform power domain was hard-capped at **55W** sustained. Because total board power exceeds 55W when the CPU draws 50W+, `psys` clamped sustained power even if package PL1 was raised.

---

## 📊 Benchmark Results

Tested on **Intel Core Ultra 5 225H** (14 cores, 14 threads) running all-core AVX2 matrix workloads:

| Metric | Stock Linux | With This Fix | Windows Reference | Delta |
| :--- | :--- | :--- | :--- | :--- |
| **Package Power (`PkgWatt`)** | 21.91 W | **62.58 W** | ~62.0 W | **+185% (~2.85x power)** |
| **Core Power (`CorWatt`)** | 18.18 W | **56.36 W** | ~56.0 W | **+209% (~3.1x power)** |
| **All-Core AVX2 Clocks** | 2,849 MHz | **4,122 – 4,147 MHz** | ~4,100 MHz | **+1,280 MHz (+45% clock speed)** |
| **Single-Core Boost** | ~2.9 GHz | **4,606 MHz (4.61 GHz)** | ~4.6 GHz | **Full single-core boost unlocked** |
| **MSR 0x64f Throttle Status** | `0x1100` (Bit 12 IccMax) | `0x0000` (Clear) | Unlocked | **IccMax lock completely eliminated** |
| **Thermals under 62.6W** | 61°C | **84°C – 96°C** | 85°C – 95°C | Safe (Well below 105°C $T_j\text{max}$) |

---

## 🚀 Quick Start: Live Test (No Reboot Required)

### 1. Install Prerequisites
* **Arch Linux / EndeavourOS / Manjaro**:
  ```bash
  sudo pacman -S --needed msr-tools linux-tools
  ```
* **Debian / Ubuntu / Mint**:
  ```bash
  sudo apt install msr-tools linux-tools-common linux-tools-generic
  ```
* **Fedora**:
  ```bash
  sudo dnf install msr-tools kernel-tools
  ```

### 2. Apply the Unlock in Memory
```bash
sudo modprobe msr

# 1. Clear PL4 peak power / IccMax clamp (MSR 0x601)
echo 0 | sudo tee /sys/class/powercap/intel-rapl:0/constraint_2_power_limit_uw
echo 0 | sudo tee /sys/class/powercap/intel-rapl-mmio:0/constraint_2_power_limit_uw
sudo wrmsr 0x601 0

# 2. Set Package PL1 (sustained) to 65W and PL2 (burst) to 80W
echo 65000000 | sudo tee /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw
echo 80000000 | sudo tee /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw
echo 65000000 | sudo tee /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw

# 3. Raise psys (Platform System Power) limits
echo 75000000 | sudo tee /sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw
echo 85000000 | sudo tee /sys/class/powercap/intel-rapl:1/constraint_1_power_limit_uw

# 4. Enable power floor on thermal PCI device (0000:00:04.0)
if [ -f /sys/bus/pci/devices/0000:00:04.0/power_limits/power_floor_enable ]; then
    echo 1 | sudo tee /sys/bus/pci/devices/0000:00:04.0/power_limits/power_floor_enable
fi
```

### 3. Verify
Run an all-core workload and monitor in real time:
```bash
sudo turbostat --Summary --quiet --show PkgWatt,CorWatt,Bzy_MHz,PkgTmp --interval 1
```

---

## 🛠️ Permanent Installation (Persists Across Reboots & Sleep)

### Step 1: Install the Unlock Script
Create `/usr/local/bin/intel-power-unlock.sh`:

```bash
sudo bash -c 'cat << "EOF" > /usr/local/bin/intel-power-unlock.sh
#!/bin/bash
# Intel Arrow Lake-H Power Limit & VR Current Uncapper

# 1. Clear PL4 / IccMax constraint (MSR 0x601)
if [ -f /sys/class/powercap/intel-rapl:0/constraint_2_power_limit_uw ]; then
    echo 0 > /sys/class/powercap/intel-rapl:0/constraint_2_power_limit_uw 2>/dev/null || true
fi
if [ -f /sys/class/powercap/intel-rapl-mmio:0/constraint_2_power_limit_uw ]; then
    echo 0 > /sys/class/powercap/intel-rapl-mmio:0/constraint_2_power_limit_uw 2>/dev/null || true
fi
wrmsr 0x601 0 2>/dev/null || true

# 2. Set Package PL1 to 65W and PL2 to 80W
if [ -f /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ]; then
    echo 65000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || true
fi
if [ -f /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw ]; then
    echo 65000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw 2>/dev/null || true
fi

# 3. Raise psys (Platform System Power) limits
if [ -f /sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw ]; then
    echo 75000000 > /sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw 2>/dev/null || true
fi
if [ -f /sys/class/powercap/intel-rapl:1/constraint_1_power_limit_uw ]; then
    echo 85000000 > /sys/class/powercap/intel-rapl:1/constraint_1_power_limit_uw 2>/dev/null || true
fi

# 4. Enable power floor on thermal PCI device
if [ -f /sys/bus/pci/devices/0000:00:04.0/power_limits/power_floor_enable ]; then
    echo 1 > /sys/bus/pci/devices/0000:00:04.0/power_limits/power_floor_enable 2>/dev/null || true
fi
EOF

chmod +x /usr/local/bin/intel-power-unlock.sh
'
```

### Step 2: Install and Enable the Systemd Service
Hooks into both system startup and wakeup from suspend:

```bash
sudo bash -c 'cat << "EOF" > /etc/systemd/system/intel-power-unlock.service
[Unit]
Description=Intel Arrow Lake-H Power Limit and Current Unlock
After=multi-user.target sleep.target thermald.service tuned.service
Wants=sleep.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/intel-power-unlock.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target sleep.target
EOF

systemctl daemon-reload
systemctl enable --now intel-power-unlock.service
'
```

### Step 3: Verify Service Status
```bash
systemctl status intel-power-unlock.service
```
It should display: `Active: active (exited)` with `status=0/SUCCESS`.

---

## 🔒 Safety & Hardware Notes

* **Silicon Thermal Protection Unaffected**: Intel hardware thermal protection (`PROCHOT` and automatic clock throttling at $T_j\text{max} = 105^\circ\text{C}$) remains completely active and untouched at the silicon level. The processor will protect itself if thermal cooling limits are reached.
* **Charger Requirements**: Ensure the laptop is powered by a compliant **65W+ or 100W USB-C Power Delivery (PD)** adapter or the OEM charger. On battery or weak 45W chargers, the Embedded Controller (EC) legitimately clamps sustained draw to prevent voltage sags.
* **Daemon Compatibility**: This service works seamlessly alongside power daemons including `power-profiles-daemon`, `tuned`, and `thermald`.

---

## 📄 License

MIT License. Contributions and feedback for other laptop models and platforms are welcome!
