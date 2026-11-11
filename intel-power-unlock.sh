#!/bin/bash
# Intel Arrow Lake-H Power Limit & VR Current Uncapper
# Removes the 22W throttle trap caused by low MSR 0x601 / constraint_2 (PL4) and restrictive psys limits

# 1. Disable / raise Peak Power (PL4 / MSR 0x601) to eliminate EDP / IccMax throttling
if [ -f /sys/class/powercap/intel-rapl:0/constraint_2_power_limit_uw ]; then
    echo 0 > /sys/class/powercap/intel-rapl:0/constraint_2_power_limit_uw 2>/dev/null || true
fi
if [ -f /sys/class/powercap/intel-rapl-mmio:0/constraint_2_power_limit_uw ]; then
    echo 0 > /sys/class/powercap/intel-rapl-mmio:0/constraint_2_power_limit_uw 2>/dev/null || true
fi
wrmsr 0x601 0 2>/dev/null || true

# 2. Set Package PL1 (sustained) to 65W and PL2 (burst) to 80W
if [ -f /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ]; then
    echo 65000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || true
fi
if [ -f /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw ]; then
    echo 65000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw 2>/dev/null || true
fi

# 3. Raise psys (Platform System Power) limits so package power can reach 62W+
if [ -f /sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw ]; then
    echo 75000000 > /sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw 2>/dev/null || true
fi
if [ -f /sys/class/powercap/intel-rapl:1/constraint_1_power_limit_uw ]; then
    echo 85000000 > /sys/class/powercap/intel-rapl:1/constraint_1_power_limit_uw 2>/dev/null || true
fi

# 4. Enable power floor on processor thermal PCI device
if [ -f /sys/bus/pci/devices/0000:00:04.0/power_limits/power_floor_enable ]; then
    echo 1 > /sys/bus/pci/devices/0000:00:04.0/power_limits/power_floor_enable 2>/dev/null || true
fi
