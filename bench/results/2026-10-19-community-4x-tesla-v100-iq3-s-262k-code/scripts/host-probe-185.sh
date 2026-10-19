#!/usr/bin/env bash
# Reads the host provenance of the benchmark machine: platform (DMI), CPU, memory,
# storage, network, the PCIe path to the GPUs, the GPU modules themselves and NVLink.
# Every value here is what the OS reports; nothing needs root on this machine.
# Physical properties of the build (the SXM2 carrier board model, the liquid cooling)
# are not readable from software and are recorded in the README instead.
#
# Run: bash host-probe-185.sh > host-provenance.txt
set -u

echo "# When this was read"
echo "  date: $(date -Is)"
echo "  This probe ran after the measurement session of 2026-10-19 had finished. The values that were"
echo "  collected during the runs live in the other files of this report: runs*.json (timings),"
echo "  memory-samples.csv (VRAM/RAM every 2 s), env.json (the server side of the provenance)."
echo "  The idle GPU readings below are the state of the machine at the moment of the probe."
echo

echo "== platform (DMI)"
for f in sys_vendor board_vendor bios_vendor product_name product_version board_name bios_version bios_date chassis_type; do
  printf "%-14s " "$f"; cat "/sys/class/dmi/id/$f" 2>/dev/null || echo "(not readable)"
done
echo "UEFI boot: $([ -d /sys/firmware/efi ] && echo yes || echo no)"

echo
echo "== CPU"
LC_ALL=C lscpu | grep -E "^(Architecture|Vendor|CPU family|Model name|Stepping|Socket|Thread|Core|CPU\(s\)|NUMA node\(s\)|L3 cache|CPU max MHz|CPU min MHz)"

echo
echo "== memory"
grep -E "^MemTotal|^MemAvailable" /proc/meminfo
echo "DIMM slots visible in the EDAC sysfs (module sizes need root):"
for d in /sys/devices/system/edac/mc/mc*/dimm*; do
  printf "  %s " "${d##*/}"; cat "$d/dimm_label" 2>/dev/null; echo
done

echo
echo "== storage"
LC_ALL=C lsblk -d -b -o NAME,MODEL,SIZE,TYPE,FSTYPE | grep -v loop
echo "filesystems:"
LC_ALL=C lsblk -fno NAME,FSTYPE,SIZE,MOUNTPOINT | grep -v loop
echo "the model files of this benchmark:"
python3 - <<'PY'
import json
c = json.load(open("/home/dgbox/strata185/Strata/strata-185-iq3_s.json"))
def walk(node, path=""):
    if isinstance(node, dict):
        for k, v in node.items(): walk(v, f"{path}.{k}" if path else k)
    elif isinstance(node, str) and node.startswith("/") and path.split(".")[-1] in ("exe", "tokenizer", "model", "mmproj", "expert_profile_save"):
        print(f"  {path} = {node}")
walk(c)
PY

echo
echo "== network"
lspci -nn | grep -iE "ethernet controller|network controller"

echo
echo "== the PCIe path to the GPUs"
echo "root port that hosts them:"
for f in vendor device current_link_width current_link_speed max_link_width max_link_speed; do
  printf "  0000:00:01.0 %-20s " "$f"; cat "/sys/bus/pci/devices/0000:00:01.0/$f" 2>/dev/null
done
echo "switch between the root port and the cards:"
lspci -nn | grep -iE "PLX|Broadcom|PEX" | head -6
echo "each GPU's own link:"
for d in 0000:03:00.0 0000:04:00.0 0000:05:00.0 0000:06:00.0; do
  printf "  %s width=" "$d"; cat "/sys/bus/pci/devices/$d/current_link_width" 2>/dev/null | tr -d '\n'
  printf " speed="; cat "/sys/bus/pci/devices/$d/current_link_speed" 2>/dev/null | tr -d '\n'
  echo
done
echo "GPU devices as the PCI layer sees them:"
lspci -nn | grep -iE "3D controller|NVIDIA"

echo
echo "== GPU modules"
nvidia-smi --query-gpu=index,name,serial,pci.bus_id,compute_cap,memory.total,power.limit,clocks.max.sm,clocks.max.memory,persistence_mode --format=csv,noheader
nvidia-smi --query-gpu=index,clocks.current.sm,clocks.current.memory,temperature.gpu,power.draw --format=csv,noheader

echo
echo "== NVLink"
nvidia-smi topo -m
nvidia-smi nvlink -s | head -30

echo
echo "== software"
lsb_release -ds 2>/dev/null; uname -r
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1
echo "system CUDA: $(command -v nvcc >/dev/null 2>&1 && echo present || echo 'not installed - nvcc is not in PATH')"
echo "system compiler in PATH: $(gcc --version 2>/dev/null | head -1 || echo none)"
echo "the toolchain the builds of both engines actually used (the paths are from bin/build-0.1.45.sh):"
echo "  nvcc: $( ~/strata185/cuda-12.8/bin/nvcc --version 2>/dev/null | grep -o 'release [0-9.]*' || echo '(not found)')  at ~/strata185/cuda-12.8/bin/nvcc"
echo "  gcc:  $( ~/strata185/gcc185/usr/bin/gcc-14 --version 2>/dev/null | head -1 || echo '(not found)')  at ~/strata185/gcc185/usr/bin/gcc-14"
