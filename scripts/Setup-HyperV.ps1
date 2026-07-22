<#
.SYNOPSIS
    Hyper-V setup helper called by the Inno Setup installer.
    Actions: EnableHyperV | CreateNetwork | CreateVMs | ConfigureNAT

.PARAMETER Action
    Which phase to execute.

.PARAMETER VHDXDir
    Directory where the golden VHDXs were copied (used by CreateVMs).
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('EnableHyperV','CreateNetwork','CreateVMs','ConfigureNAT')]
    [string]$Action,

    [string]$VHDXDir = "$env:ProgramData\AllInOneDevStack\VMs"
)

$ErrorActionPreference = 'Stop'
$LogFile = "$env:ProgramData\AllInOneDevStack\install.log"
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null

function Write-Log {
    param([string]$Msg)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts  $Msg" | Tee-Object -FilePath $LogFile -Append | Out-Null
    Write-Host $Msg
}

# ─────────────────────────────────────────────────────────────────────────────
# Shared constants — must match installer.iss registry values
# ─────────────────────────────────────────────────────────────────────────────
$SwitchName      = 'AllInOneSwitch'
$NATName         = 'AllInOneNAT'
$NATSubnet       = '192.168.100.0/24'
$GatewayIP       = '192.168.100.1'
$GitLabVMName    = 'GitLabVM'
$GitLabVMIP      = '192.168.100.10'
$MattermostVMName= 'MattermostVM'
$MattermostVMIP  = '192.168.100.11'
$NextjsVMName    = 'NextjsVM'
$NextjsVMIP      = '192.168.100.12'
$GitLabWebPort   = 8090
$GitLabSSHPort   = 2222
$MattermostPort  = 8065
$NextjsPort      = 3000

# ─────────────────────────────────────────────────────────────────────────────
switch ($Action) {

# ─────────────────────────────────────────────────────────────────────────────
'EnableHyperV' {
    Write-Log "=== ACTION: EnableHyperV ==="

    # Try 'Microsoft-Hyper-V-All' (desktop Windows); fall back to 'Microsoft-Hyper-V' (Server)
    $featureName = 'Microsoft-Hyper-V-All'
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
    } catch {
        $featureName = 'Microsoft-Hyper-V'
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
    }

    if ($feature.State -eq 'Enabled') {
        Write-Log "Hyper-V is already enabled — skipping."
        exit 0
    }

    Write-Log "Enabling Hyper-V feature ($featureName)..."
    $result = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart
    if ($result.RestartNeeded) {
        Write-Log "Reboot required. Inno Setup will handle the restart."
        exit 3010
    }
    Write-Log "Hyper-V enabled without reboot."
}

# ─────────────────────────────────────────────────────────────────────────────
'CreateNetwork' {
    Write-Log "=== ACTION: CreateNetwork ==="

    # Internal switch
    if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
        Write-Log "Creating internal VM switch: $SwitchName"
        New-VMSwitch -Name $SwitchName -SwitchType Internal
    } else {
        Write-Log "Switch $SwitchName already exists — skipping."
    }

    # Assign gateway IP to the host adapter
    # Use -First 1 in case multiple adapters match (prevents array-to-cmdlet errors)
    $adapterIndex = (Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" } | Select-Object -First 1).ifIndex
    if ($adapterIndex) {
        $existing = Get-NetIPAddress -InterfaceIndex $adapterIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Log "Assigning gateway IP $GatewayIP to host adapter..."
            New-NetIPAddress -IPAddress $GatewayIP -PrefixLength 24 -InterfaceIndex $adapterIndex
        } else {
            Write-Log "Host adapter already has IP $($existing.IPAddress) — skipping."
        }
    }

    # Windows NAT
    if (-not (Get-NetNat -Name $NATName -ErrorAction SilentlyContinue)) {
        Write-Log "Creating NAT: $NATName -> $NATSubnet"
        New-NetNat -Name $NATName -InternalIPInterfaceAddressPrefix $NATSubnet
    } else {
        Write-Log "NAT $NATName already exists — skipping."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
'CreateVMs' {
    Write-Log "=== ACTION: CreateVMs (VHDXDir=$VHDXDir) ==="

    $vmConfigs = @(
        @{ Name=$GitLabVMName;     VHDX="$VHDXDir\GitLabVM.vhdx";     RAM=4GB; CPU=2 }
        @{ Name=$MattermostVMName; VHDX="$VHDXDir\MattermostVM.vhdx"; RAM=2GB; CPU=2 }
        @{ Name=$NextjsVMName;     VHDX="$VHDXDir\NextjsVM.vhdx";     RAM=1GB; CPU=1 }
    )

    foreach ($cfg in $vmConfigs) {
        if (Get-VM -Name $cfg.Name -ErrorAction SilentlyContinue) {
            Write-Log "VM $($cfg.Name) already exists — skipping creation."
            continue
        }

        if (-not (Test-Path $cfg.VHDX)) {
            Write-Log "ERROR: VHDX not found at $($cfg.VHDX). Aborting."
            exit 1
        }

        Write-Log "Creating VM: $($cfg.Name) [RAM=$($cfg.RAM/1GB)GB, CPU=$($cfg.CPU)]"
        New-VM `
            -Name $cfg.Name `
            -MemoryStartupBytes $cfg.RAM `
            -VHDPath $cfg.VHDX `
            -Generation 2 `
            -SwitchName $SwitchName | Out-Null

        Set-VM -Name $cfg.Name `
            -ProcessorCount $cfg.CPU `
            -AutomaticStartAction Start `
            -AutomaticStartDelay 30 `
            -AutomaticStopAction Shutdown `
            -CheckpointType Disabled

        # Secure boot: Ubuntu needs the Microsoft UEFI CA template
        Set-VMFirmware -VMName $cfg.Name -SecureBootTemplate MicrosoftUEFICertificateAuthority

        Write-Log "VM $($cfg.Name) created successfully."
    }
}

# ─────────────────────────────────────────────────────────────────────────────
'ConfigureNAT' {
    Write-Log "=== ACTION: ConfigureNAT ==="

    # Helper to add a NAT static mapping safely
    function Add-NATRule {
        param([string]$Proto, [int]$ExternalPort, [string]$InternalIP, [int]$InternalPort)
        $existing = Get-NetNatStaticMapping -NatName $NATName -ErrorAction SilentlyContinue |
                    Where-Object { $_.ExternalPort -eq $ExternalPort -and $_.Protocol -eq $Proto }
        if ($existing) {
            Write-Log "NAT rule $Proto/$ExternalPort already exists — skipping."
            return
        }
        Write-Log "Adding NAT rule: host:$ExternalPort -> ${InternalIP}:${InternalPort} ($Proto)"
        Add-NetNatStaticMapping `
            -NatName $NATName `
            -Protocol $Proto `
            -ExternalIPAddress '0.0.0.0' `
            -ExternalPort $ExternalPort `
            -InternalIPAddress $InternalIP `
            -InternalPort $InternalPort
    }

    # GitLab
    Add-NATRule -Proto TCP -ExternalPort $GitLabWebPort -InternalIP $GitLabVMIP -InternalPort 80
    Add-NATRule -Proto TCP -ExternalPort $GitLabSSHPort -InternalIP $GitLabVMIP -InternalPort 22

    # Mattermost
    Add-NATRule -Proto TCP -ExternalPort $MattermostPort -InternalIP $MattermostVMIP -InternalPort 8065

    # Next.js
    Add-NATRule -Proto TCP -ExternalPort $NextjsPort -InternalIP $NextjsVMIP -InternalPort 3000

    Write-Log "NAT rules configured."
}

} # end switch
