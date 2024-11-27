#version 1.0
param (
    [string]$action = "",
    [int]$gpuNumber = -1,
    [int]$vmNumber = -1,
    [switch]$dryRun
)

# Improved logging function
function Write-Status {
    param ([string]$Message)
    Write-Host "[STATUS] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Check-IOMMU {
    Write-Status "Checking system IOMMU support..."
    $iovSupport = (Get-VMHost).IovSupport
    $iovSupportReasons = (Get-VMHost).IovSupportReasons
    if ($iovSupport -eq $false) {
        Write-Host "IOMMU is not supported on this host. DDA requires IOMMU support." -ForegroundColor Red
        Write-Host "Reasons: $iovSupportReasons" -ForegroundColor Yellow
        return $false
    } else {
        Write-Host "IOMMU support is enabled on this host." -ForegroundColor Green
        return $true
    }
}

function Get-AvailableGPUs {
    Write-Status "Discovering available GPUs (including disabled)..."
    # Include all display devices, regardless of status
    $gpus = Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like "PCI*" }
    $gpuList = @()
    $index = 1

    Write-Host "Available GPUs:" -ForegroundColor Cyan
    foreach ($gpu in $gpus) {
        # Improved location path retrieval
        $locationPath = $null
        try {
            $locationPath = (Get-PnpDeviceProperty -InstanceID $gpu.InstanceId -KeyName "DEVPKEY_Device_LocationPaths").Data
        } catch {
            $locationPath = "Location Path Unavailable"
        }

        $gpuList += [PSCustomObject]@{ 
            Number = $index
            Name = $gpu.FriendlyName
            DeviceID = $gpu.DeviceId
            LocationPath = $locationPath
            Status = $gpu.Status
        }
        Write-Host "$index. $($gpu.FriendlyName) (Status: $($gpu.Status))" -ForegroundColor White
	#Write-Host "  DeviceID: $($gpu.DeviceId)" -ForegroundColor Gray
        #Write-Host "  LocationPath: $($locationPath)" -ForegroundColor Gray
        #Write-Host "  Status: $($gpu.Status)" -ForegroundColor Gray
        $index++
    }
    return $gpuList
}

function Get-AvailableVMs {
    Write-Status "Discovering available Virtual Machines..."
    $vms = Get-VM
    $vmList = @()
    $index = 1

    Write-Host "Available VMs:" -ForegroundColor Cyan
    foreach ($vm in $vms) {
        $vmList += [PSCustomObject]@{ Number = $index; Name = $vm.Name; Status = $vm.State }
        Write-Host "$index. $($vm.Name) - Status: $($vm.State)" -ForegroundColor White
        $index++
    }
    return $vmList
}

function Show-GPUMappings {
    Write-Status "Checking current GPU-to-VM mappings..."
    
    # Get all PnP devices, including those that might be disabled
    $allGPUs = Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like "PCI*" }
    
    $mappedDevices = Get-VM | ForEach-Object {
        $vm = $_
        $assignedDevices = Get-VMAssignableDevice -VMName $vm.Name -ErrorAction SilentlyContinue
        foreach ($device in $assignedDevices) {
            # Find matching GPU by EXACT LocationPath
            $matchingGPU = $allGPUs | Where-Object { 
                $locationPath = $null
                try {
                    $locationPath = (Get-PnpDeviceProperty -InstanceID $_.InstanceId -KeyName "DEVPKEY_Device_LocationPaths").Data
                } catch {
                    $locationPath = $null
                }
                $locationPath -eq $device.LocationPath
            }

            $gpuName = "Unknown GPU"
            $deviceStatus = "Not Found"
            if ($matchingGPU) {
                $gpuName = $matchingGPU.FriendlyName
                $deviceStatus = $matchingGPU.Status
            }

            [PSCustomObject]@{
                VMName = $vm.Name
                VMStatus = $vm.State
                DeviceID = $device.DeviceID
                LocationPath = $device.LocationPath
                GPUName = $gpuName
                DeviceStatus = $deviceStatus
            }
        }
    }

    if ($mappedDevices) {
        Write-Host "Current GPU-to-VM Mappings:" -ForegroundColor Cyan
        foreach ($device in $mappedDevices) {
            Write-Host "GPU: $($device.GPUName) <-> VM: $($device.VMName)" -ForegroundColor White
            Write-Host "  LocationPath: $($device.LocationPath)" -ForegroundColor Gray

        }
    } else {
        Write-Host "No GPUs currently mapped to VMs." -ForegroundColor Yellow
    }
}


function Map-GPUToVM {
    param (
        [PSCustomObject]$gpu,
        [PSCustomObject]$vm,
        [switch]$dryRun
    )

    if ($dryRun) {
        Write-Output "[DRY RUN] Would assign GPU '$($gpu.Name)' to VM '$($vm.Name)'."
        return
    }

    # Disable the GPU on the host
    Write-Output "Dismounting GPU from the host at $($gpu.LocationPath)..."
    Dismount-VmHostAssignableDevice -LocationPath $gpu.LocationPath -Force

    # Configure VM for DDA
    Write-Output "Configuring cache and memory for DDA..."
    Set-VM -Name $vm.Name -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 3GB -HighMemoryMappedIoSpace 33280MB

    # Add the GPU as an assignable device
    Write-Output "Assigning GPU to VM '$($vm.Name)'..."
    Add-VMAssignableDevice -VMName $vm.Name -LocationPath $gpu.LocationPath
    Write-Output "GPU '$($gpu.Name)' assigned to VM '$($vm.Name)'."
}

function Unmap-GPUFromVM {
    param (
        [PSCustomObject]$vm,
        [switch]$dryRun
    )

    $assignedDevices = Get-VMAssignableDevice -VMName $vm.Name -ErrorAction SilentlyContinue
    foreach ($device in $assignedDevices) {
        if ($dryRun) {
            Write-Output "[DRY RUN] Would unmap GPU with LocationPath '$($device.LocationPath)' from VM '$($vm.Name)'."
        } else {
            Write-Output "Unmapping GPU from VM '$($vm.Name)'..."
            Remove-VMAssignableDevice -VMName $vm.Name -LocationPath $device.LocationPath
            Write-Output "GPU unmapped from VM '$($vm.Name)'."
        }
    }
}

# Main Program
if (-not $action) {
    # No action specified, just display available GPUs, VMs, and current mappings
    if (Check-IOMMU) {
        $gpuList = Get-AvailableGPUs
        $vmList = Get-AvailableVMs
        Show-GPUMappings
    }
} elseif ($action -eq "mapGPU" -and $gpuNumber -ne -1 -and $vmNumber -ne -1) {
    # Map GPU to VM
    $gpuList = Get-AvailableGPUs
    $vmList = Get-AvailableVMs
    $selectedGPU = $gpuList | Where-Object { $_.Number -eq $gpuNumber }
    $selectedVM = $vmList | Where-Object { $_.Number -eq $vmNumber }

    if ($selectedGPU -and $selectedVM) {
        Write-Output "nYou are about to map GPU '$($selectedGPU.Name)' to VM '$($selectedVM.Name)'."
        $confirm = Read-Host "Confirm? (Y/N)"
        if ($confirm -eq 'Y') {
            Map-GPUToVM -gpu $selectedGPU -vm $selectedVM -dryRun:$dryRun
        } else {
            Write-Output "Mapping canceled."
        }
    } else {
        Write-Output "Invalid GPU or VM selection."
    }
} elseif ($action -eq "unmap" -and $vmNumber -ne -1) {
    # Unmap GPU from VM
    $vmList = Get-AvailableVMs
    $selectedVM = $vmList | Where-Object { $_.Number -eq $vmNumber }

    if ($selectedVM) {
        Write-Output "nYou are about to unmap all GPUs from VM '$($selectedVM.Name)'."
        $confirm = Read-Host "Confirm? (Y/N)"
        if ($confirm -eq 'Y') {
            Unmap-GPUFromVM -vm $selectedVM -dryRun:$dryRun
        } else {
            Write-Output "Unmapping canceled."
        }
    } else {
        Write-Output "Invalid VM selection."
    }
} else {
    Write-Output "Invalid action or parameters. Use 'mapGPU [GPU number] [VM number]' or 'unmap [VM number]'."
}