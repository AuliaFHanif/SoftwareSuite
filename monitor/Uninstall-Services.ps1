<#
.SYNOPSIS
    Uninstall-Services.ps1
    Called by the Inno Setup uninstaller to cleanly remove all AllInOne services.
    Stops and deletes both Hyper-V VMs, removes the NAT and virtual switch.
#>

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Stopping GitLabVM..."
Stop-VM -Name 'GitLabVM' -Force
Write-Host "Stopping MattermostVM..."
Stop-VM -Name 'MattermostVM' -Force

Write-Host "Removing GitLabVM..."
Remove-VM -Name 'GitLabVM' -Force
Write-Host "Removing MattermostVM..."
Remove-VM -Name 'MattermostVM' -Force

Write-Host "Removing NAT..."
Remove-NetNat -Name 'AllInOneNAT' -Confirm:$false

Write-Host "Removing virtual switch..."
Remove-VMSwitch -Name 'AllInOneSwitch' -Force

Write-Host "Uninstall complete."
