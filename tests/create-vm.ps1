#Requires -RunAsAdministrator
# tests/create-vm.ps1 — Create a Hyper-V VM for testing the Debian server installer
# Usage: Run from an elevated PowerShell prompt:
#   .\tests\create-vm.ps1

$ErrorActionPreference = "Stop"

# --- Configuration ---
$VMName        = "debian-server-test"
$VMPath        = "D:\VMs"
$ISOPath       = "D:\dev\dev\configs\debian-server\iso\out\debian-server-custom-2026.02.25-amd64.iso"
$VHDXPath      = "$VMPath\$VMName\$VMName.vhdx"
$MemoryStartup = 4GB
$DiskSize      = 60GB
$CPUCount      = 2

# --- Preflight ---
if (!(Test-Path $ISOPath)) {
    Write-Error "ISO not found at $ISOPath"
    exit 1
}

# Pick a virtual switch (prefer External, fall back to Default Switch)
$Switch = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1
if (-not $Switch) {
    $Switch = Get-VMSwitch | Where-Object { $_.Name -eq "Default Switch" } | Select-Object -First 1
}
if (-not $Switch) {
    $Switch = Get-VMSwitch | Select-Object -First 1
}
if (-not $Switch) {
    Write-Error "No Hyper-V virtual switch found. Create one in Hyper-V Manager first."
    exit 1
}
Write-Host "Using virtual switch: $($Switch.Name)" -ForegroundColor Cyan

# --- Remove existing VM if present ---
$existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing VM '$VMName'..." -ForegroundColor Yellow
    if ($existing.State -ne "Off") {
        Stop-VM -Name $VMName -Force -TurnOff
    }
    Remove-VM -Name $VMName -Force
    if (Test-Path $VHDXPath) {
        Remove-Item $VHDXPath -Force
    }
}

# --- Create VM ---
Write-Host "Creating VM '$VMName'..." -ForegroundColor Green

New-VM -Name $VMName `
    -MemoryStartupBytes $MemoryStartup `
    -Generation 2 `
    -NewVHDPath $VHDXPath `
    -NewVHDSizeBytes $DiskSize `
    -SwitchName $Switch.Name `
    -Path $VMPath

# CPU
Set-VMProcessor -VMName $VMName -Count $CPUCount

# Disable Secure Boot (Linux ISO won't have Microsoft signatures)
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off

# Attach ISO
Add-VMDvdDrive -VMName $VMName -Path $ISOPath

# Set boot order: DVD first, then hard drive
$dvd = Get-VMDvdDrive -VMName $VMName
$hdd = Get-VMHardDiskDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -BootOrder $dvd, $hdd

# Disable checkpoints (not needed for testing)
Set-VM -VMName $VMName -CheckpointType Disabled

Write-Host ""
Write-Host "VM '$VMName' created successfully!" -ForegroundColor Green
Write-Host "  Memory:  $($MemoryStartup / 1GB) GB" -ForegroundColor White
Write-Host "  CPUs:    $CPUCount" -ForegroundColor White
Write-Host "  Disk:    $($DiskSize / 1GB) GB" -ForegroundColor White
Write-Host "  Switch:  $($Switch.Name)" -ForegroundColor White
Write-Host "  ISO:     $ISOPath" -ForegroundColor White
Write-Host ""
Write-Host "Start with:" -ForegroundColor Cyan
Write-Host "  Start-VM -Name '$VMName'" -ForegroundColor White
Write-Host "  vmconnect localhost '$VMName'" -ForegroundColor White
