# GPU Passthrough Management Script for DDA (Discrete Device Assignment)

This PowerShell script (`gpu-passthrough.ps1`) enables administrators to manage GPU mappings for Hyper-V virtual machines (VMs) using Discrete Device Assignment (DDA). It includes functionality to discover available GPUs and VMs, map GPUs to VMs, unmap GPUs, and revert associated settings.

---

## Features

- **Discover GPUs and VMs**: Lists all available GPUs and VMs with detailed information.
- **GPU-to-VM Mapping**: Assigns GPUs to VMs with necessary configuration for DDA.
- **GPU Unmapping**: Removes GPU mappings from VMs and reverts VM configuration changes.
- **IOMMU Check**: Verifies if the system supports IOMMU, a prerequisite for DDA.
- **Dry Run Mode**: Simulates actions without making any changes.

---

## Requirements

1. Windows 10/11 or Windows Server 2016 and above.
2. Hyper-V must be enabled and configured.
3. PowerShell 5.1 or later.

---

## Script Usage

### Parameters

| Parameter       | Description                                                                                             | Default Value |
|-----------------|---------------------------------------------------------------------------------------------------------|---------------|
| `-action`       | Specifies the action to perform. Valid values: `mapGPU`, `unmap`, or leave empty for a status overview. | `""`          |
| `-gpuNumber`    | Index of the GPU to be mapped. Used with `mapGPU` action.                                               | `-1`          |
| `-vmNumber`     | Index of the VM to be mapped. Used with `mapGPU` or `unmap` actions.                                    | `-1`          |
| `-dryRun`       | Simulates the action without making any changes.                                                        | `False`       |

---

### Actions

#### 1. Display Current Status
Run the script without parameters to:
- Verify IOMMU support.
- List all available GPUs and VMs.
- Display current GPU-to-VM mappings.

|---------------------------------------------------------------------------------------------------------|
```powershell
.\gpu-passthrough.ps1 -action mapGPU -gpuNumber 1 -vmNumber 2
Output:


[STATUS] Discovering available GPUs (including disabled)...
Available GPUs:
1. NVIDIA GeForce GTX 1080 (Status: OK)
2. AMD Radeon RX 6700 (Status: OK)

[STATUS] Discovering available Virtual Machines...
Available VMs:
1. VM1 - Status: Off
2. VM2 - Status: Running

You are about to map GPU 'NVIDIA GeForce GTX 1080' to VM 'VM2'.
Confirm? (Y/N): Y

Dismounting GPU from the host at PCIROOT(0)#PCI(0300)#PCI(0000)...
[STATUS] GPU successfully dismounted from the host.

Configuring VM 'VM2' for DDA...
[STATUS] VM memory and cache configured for DDA.

Assigning GPU to VM 'VM2'...
[STATUS] GPU 'NVIDIA GeForce GTX 1080' successfully assigned to VM 'VM2'.
