<#
.SYNOPSIS
    AllInOne Monitor — WPF dashboard for Hyper-V services.
    Manage GitLabVM, MattermostVM, and native Ollama from one window.
    Requires: Windows PowerShell 5.1+, Hyper-V module, Admin rights.
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# ─────────────────────────────────────────────────────────────────────────────
# Self-elevate to admin if needed
# ─────────────────────────────────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ─────────────────────────────────────────────────────────────────────────────
# Read config from registry (written by installer, editable by monitor)
# ─────────────────────────────────────────────────────────────────────────────
function Get-Config {
    $reg = 'HKLM:\SOFTWARE\AllInOneDevStack'
    # Use if/else fallbacks — the ?? operator requires PowerShell 7+
    function rv([string]$k, $d) {
        $v = Get-ItemPropertyValue $reg $k -ErrorAction SilentlyContinue
        if ($null -ne $v) { $v } else { $d }
    }
    [PSCustomObject]@{
        GitLabWebPort    = rv 'GitLabWebPort'  8090
        GitLabSSHPort    = rv 'GitLabSSHPort'  2222
        MattermostPort   = rv 'MattermostPort' 8065
        OllamaPort       = rv 'OllamaPort'     11434
        GitLabVMIP       = rv 'GitLabVMIP'     '192.168.100.10'
        MattermostVMIP   = rv 'MattermostVMIP' '192.168.100.11'
        NATName          = 'AllInOneNAT'
    }
}

function Set-ConfigValue([string]$Name, $Value) {
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\AllInOneDevStack' -Name $Name -Value $Value -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────────────────────────────
# XAML UI definition
# ─────────────────────────────────────────────────────────────────────────────
[xml]$XAML = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AllInOne Monitor" Height="680" Width="860"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#0F1117" FontFamily="Segoe UI" FontSize="13">
    <Window.Resources>
        <!-- Card style -->
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="#1A1D27"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Effect">
                <Setter.Value>
                    <DropShadowEffect Color="#000000" Opacity="0.4" BlurRadius="12" ShadowDepth="2"/>
                </Setter.Value>
            </Setter>
        </Style>
        <!-- Primary button -->
        <Style x:Key="BtnPrimary" TargetType="Button">
            <Setter Property="Background" Value="#4F6EF7"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="Margin" Value="4,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#6B85FF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#3A55D4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <!-- Stop button -->
        <Style x:Key="BtnStop" TargetType="Button" BasedOn="{StaticResource BtnPrimary}">
            <Setter Property="Background" Value="#E05260"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#F26370"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <!-- Label text -->
        <Style x:Key="LabelText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#8B93A7"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Margin" Value="0,0,0,2"/>
        </Style>
        <!-- Value text -->
        <Style x:Key="ValueText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#E2E8F4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <!-- Section header -->
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#E2E8F4"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>
        <!-- Port input -->
        <Style x:Key="PortInput" TargetType="TextBox">
            <Setter Property="Background" Value="#0F1117"/>
            <Setter Property="Foreground" Value="#E2E8F4"/>
            <Setter Property="BorderBrush" Value="#2D3348"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="Width" Value="80"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
    </Window.Resources>

    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#1A1D27" CornerRadius="10" Padding="20,14" Margin="6,6,6,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="AllInOne Monitor" FontSize="22" FontWeight="Bold" Foreground="#E2E8F4"/>
                    <TextBlock x:Name="SubTitle" Text="Air-Gapped DevStack — Hyper-V Edition"
                               FontSize="12" Foreground="#8B93A7" Margin="0,2,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="Last updated: " Style="{StaticResource LabelText}" VerticalAlignment="Center"/>
                    <TextBlock x:Name="LastUpdated" Text="—" Style="{StaticResource LabelText}" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main content -->
        <Grid Grid.Row="1" Margin="0,6,0,0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- GitLab Card -->
            <Border Grid.Row="0" Style="{StaticResource Card}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Status LED + name -->
                    <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,20,0">
                        <Ellipse x:Name="GitLabLED" Width="14" Height="14" Fill="#E05260" Margin="0,0,10,0"
                                 VerticalAlignment="Center">
                            <Ellipse.Effect>
                                <DropShadowEffect Color="#E05260" Opacity="0.7" BlurRadius="6" ShadowDepth="0"/>
                            </Ellipse.Effect>
                        </Ellipse>
                        <TextBlock Text="GitLab CE" FontSize="16" FontWeight="Bold" Foreground="#E2E8F4" VerticalAlignment="Center"/>
                    </StackPanel>

                    <!-- Stats -->
                    <Grid Grid.Column="1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock Text="STATUS" Style="{StaticResource LabelText}"/>
                            <TextBlock x:Name="GitLabStatus" Text="Stopped" Style="{StaticResource ValueText}"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="CPU / RAM" Style="{StaticResource LabelText}"/>
                            <TextBlock x:Name="GitLabResources" Text="— / —" Style="{StaticResource ValueText}"/>
                        </StackPanel>
                        <StackPanel Grid.Column="2">
                            <TextBlock Text="WEB PORT / SSH PORT" Style="{StaticResource LabelText}"/>
                            <StackPanel Orientation="Horizontal">
                                <TextBox x:Name="GitLabWebPortBox" Style="{StaticResource PortInput}" Text="8090"/>
                                <TextBlock Text=" / " Foreground="#8B93A7" VerticalAlignment="Center" Margin="4,0"/>
                                <TextBox x:Name="GitLabSSHPortBox" Style="{StaticResource PortInput}" Text="2222"/>
                            </StackPanel>
                        </StackPanel>
                    </Grid>

                    <!-- Buttons -->
                    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,0,0">
                        <Button x:Name="GitLabStart" Content="▶  Start" Style="{StaticResource BtnPrimary}" Width="90"/>
                        <Button x:Name="GitLabStop"  Content="■  Stop"  Style="{StaticResource BtnStop}"    Width="90"/>
                        <Button x:Name="GitLabPort"  Content="↔ Apply Port" Style="{StaticResource BtnPrimary}" Width="110"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Mattermost Card -->
            <Border Grid.Row="1" Style="{StaticResource Card}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,20,0">
                        <Ellipse x:Name="MattermostLED" Width="14" Height="14" Fill="#E05260" Margin="0,0,10,0"
                                 VerticalAlignment="Center">
                            <Ellipse.Effect>
                                <DropShadowEffect Color="#E05260" Opacity="0.7" BlurRadius="6" ShadowDepth="0"/>
                            </Ellipse.Effect>
                        </Ellipse>
                        <TextBlock Text="Mattermost" FontSize="16" FontWeight="Bold" Foreground="#E2E8F4" VerticalAlignment="Center"/>
                    </StackPanel>

                    <Grid Grid.Column="1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock Text="STATUS" Style="{StaticResource LabelText}"/>
                            <TextBlock x:Name="MattermostStatus" Text="Stopped" Style="{StaticResource ValueText}"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="CPU / RAM" Style="{StaticResource LabelText}"/>
                            <TextBlock x:Name="MattermostResources" Text="— / —" Style="{StaticResource ValueText}"/>
                        </StackPanel>
                        <StackPanel Grid.Column="2">
                            <TextBlock Text="PORT" Style="{StaticResource LabelText}"/>
                            <TextBox x:Name="MattermostPortBox" Style="{StaticResource PortInput}" Text="8065"/>
                        </StackPanel>
                    </Grid>

                    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,0,0">
                        <Button x:Name="MattermostStart" Content="▶  Start" Style="{StaticResource BtnPrimary}" Width="90"/>
                        <Button x:Name="MattermostStop"  Content="■  Stop"  Style="{StaticResource BtnStop}"    Width="90"/>
                        <Button x:Name="MattermostPort"  Content="↔ Apply Port" Style="{StaticResource BtnPrimary}" Width="110"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Ollama Card -->
            <Border Grid.Row="2" Style="{StaticResource Card}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,20,0">
                        <Ellipse x:Name="OllamaLED" Width="14" Height="14" Fill="#E05260" Margin="0,0,10,0"
                                 VerticalAlignment="Center">
                            <Ellipse.Effect>
                                <DropShadowEffect Color="#E05260" Opacity="0.7" BlurRadius="6" ShadowDepth="0"/>
                            </Ellipse.Effect>
                        </Ellipse>
                        <TextBlock Text="Ollama" FontSize="16" FontWeight="Bold" Foreground="#E2E8F4" VerticalAlignment="Center"/>
                    </StackPanel>

                    <Grid Grid.Column="1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock Text="STATUS" Style="{StaticResource LabelText}"/>
                            <TextBlock x:Name="OllamaStatus" Text="Stopped" Style="{StaticResource ValueText}"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1">
                            <TextBlock Text="CPU / RAM" Style="{StaticResource LabelText}"/>
                            <TextBlock x:Name="OllamaResources" Text="— / —" Style="{StaticResource ValueText}"/>
                        </StackPanel>
                        <StackPanel Grid.Column="2">
                            <TextBlock Text="API PORT" Style="{StaticResource LabelText}"/>
                            <TextBox x:Name="OllamaPortBox" Style="{StaticResource PortInput}" Text="11434"/>
                        </StackPanel>
                    </Grid>

                    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,0,0">
                        <Button x:Name="OllamaStart" Content="▶  Start" Style="{StaticResource BtnPrimary}" Width="90"/>
                        <Button x:Name="OllamaStop"  Content="■  Stop"  Style="{StaticResource BtnStop}"    Width="90"/>
                        <Button x:Name="OllamaPort"  Content="↔ Apply Port" Style="{StaticResource BtnPrimary}" Width="110"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Log area -->
            <Border Grid.Row="3" Style="{StaticResource Card}">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="Activity Log" Style="{StaticResource SectionHeader}" Grid.Row="0"/>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" MaxHeight="140">
                        <TextBlock x:Name="LogBox" Foreground="#8B93A7" FontSize="11" FontFamily="Consolas"
                                   TextWrapping="Wrap" LineHeight="18"/>
                    </ScrollViewer>
                </Grid>
            </Border>
        </Grid>

        <!-- Footer -->
        <Border Grid.Row="2" Background="#1A1D27" CornerRadius="10" Padding="16,10" Margin="6,4,6,6">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                <TextBlock Text="GitLab: " Style="{StaticResource LabelText}" VerticalAlignment="Center"/>
                <TextBlock x:Name="FooterGitLab" Text="http://localhost:8090" Foreground="#4F6EF7"
                           FontSize="12" VerticalAlignment="Center" Margin="0,0,24,0" Cursor="Hand">
                    <TextBlock.InputBindings>
                        <MouseBinding MouseAction="LeftClick" Command="{x:Null}"/>
                    </TextBlock.InputBindings>
                </TextBlock>
                <TextBlock Text="Mattermost: " Style="{StaticResource LabelText}" VerticalAlignment="Center"/>
                <TextBlock x:Name="FooterMattermost" Text="http://localhost:8065" Foreground="#4F6EF7"
                           FontSize="12" VerticalAlignment="Center" Margin="0,0,24,0"/>
                <TextBlock Text="Ollama: " Style="{StaticResource LabelText}" VerticalAlignment="Center"/>
                <TextBlock x:Name="FooterOllama" Text="http://localhost:11434" Foreground="#4F6EF7"
                           FontSize="12" VerticalAlignment="Center"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
'@

# ─────────────────────────────────────────────────────────────────────────────
# Load XAML
# ─────────────────────────────────────────────────────────────────────────────
$reader = [System.Xml.XmlNodeReader]::new($XAML)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Grab named controls
function ctrl([string]$n) { $window.FindName($n) }

$cfg = Get-Config

# Pre-fill port boxes from registry
(ctrl 'GitLabWebPortBox').Text  = $cfg.GitLabWebPort
(ctrl 'GitLabSSHPortBox').Text  = $cfg.GitLabSSHPort
(ctrl 'MattermostPortBox').Text = $cfg.MattermostPort
(ctrl 'OllamaPortBox').Text     = $cfg.OllamaPort
(ctrl 'FooterGitLab').Text      = "http://localhost:$($cfg.GitLabWebPort)"
(ctrl 'FooterMattermost').Text  = "http://localhost:$($cfg.MattermostPort)"
(ctrl 'FooterOllama').Text      = "http://localhost:$($cfg.OllamaPort)"

# ─────────────────────────────────────────────────────────────────────────────
# Logging helper
# ─────────────────────────────────────────────────────────────────────────────
function Write-UILog([string]$Msg) {
    $ts  = Get-Date -Format 'HH:mm:ss'
    $box = ctrl 'LogBox'
    $box.Text += "[$ts] $Msg`n"
    # Auto-scroll
    $sv = $box.Parent
    if ($sv -is [System.Windows.Controls.ScrollViewer]) { $sv.ScrollToBottom() }
}

# ─────────────────────────────────────────────────────────────────────────────
# LED + status helper
# ─────────────────────────────────────────────────────────────────────────────
function Set-ServiceStatus([string]$Prefix, [string]$State) {
    $led    = ctrl "${Prefix}LED"
    $label  = ctrl "${Prefix}Status"
    switch ($State) {
        'Running' {
            $led.Fill   = [Windows.Media.Brushes]::LimeGreen
            ($led.Effect).Color = [Windows.Media.Color]::FromRgb(0x32,0xCD,0x32)
            $label.Text = 'Running'
            $label.Foreground = [Windows.Media.Brushes]::LimeGreen
        }
        'Starting' {
            $led.Fill   = [Windows.Media.Brushes]::Orange
            ($led.Effect).Color = [Windows.Media.Color]::FromRgb(0xFF,0xA5,0x00)
            $label.Text = 'Starting…'
            $label.Foreground = [Windows.Media.Brushes]::Orange
        }
        default {
            $brush = [Windows.Media.BrushConverter]::new().ConvertFromString('#E05260')
            $led.Fill   = $brush
            ($led.Effect).Color = [Windows.Media.Color]::FromRgb(0xE0,0x52,0x60)
            $label.Text = 'Stopped'
            $label.Foreground = $brush
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Refresh stats (called by timer every 5s)
# ─────────────────────────────────────────────────────────────────────────────
function Refresh-Stats {
    (ctrl 'LastUpdated').Text = (Get-Date -Format 'HH:mm:ss')

    # GitLab VM
    try {
        $vm = Get-VM -Name 'GitLabVM' -ErrorAction Stop
        Set-ServiceStatus 'GitLab' $(if ($vm.State -eq 'Running') {'Running'} else {'Stopped'})
        if ($vm.State -eq 'Running') {
            $m = Measure-VM -VMName 'GitLabVM' -ErrorAction SilentlyContinue
            $cpu = if ($m) { "$([math]::Round($m.AvgCPUUsage,1))%" } else { "?%" }
            $ram = if ($m) { "$([math]::Round($m.AvgRAMUsage/1MB,0)) MB" } else { "? MB" }
            (ctrl 'GitLabResources').Text = "$cpu / $ram"
        } else { (ctrl 'GitLabResources').Text = "— / —" }
    } catch {
        Set-ServiceStatus 'GitLab' 'Stopped'
        (ctrl 'GitLabResources').Text = "VM not found"
    }

    # Mattermost VM
    try {
        $vm = Get-VM -Name 'MattermostVM' -ErrorAction Stop
        Set-ServiceStatus 'Mattermost' $(if ($vm.State -eq 'Running') {'Running'} else {'Stopped'})
        if ($vm.State -eq 'Running') {
            $m = Measure-VM -VMName 'MattermostVM' -ErrorAction SilentlyContinue
            $cpu = if ($m) { "$([math]::Round($m.AvgCPUUsage,1))%" } else { "?%" }
            $ram = if ($m) { "$([math]::Round($m.AvgRAMUsage/1MB,0)) MB" } else { "? MB" }
            (ctrl 'MattermostResources').Text = "$cpu / $ram"
        } else { (ctrl 'MattermostResources').Text = "— / —" }
    } catch {
        Set-ServiceStatus 'Mattermost' 'Stopped'
        (ctrl 'MattermostResources').Text = "VM not found"
    }

    # Ollama — check if the service/process is running
    $svc  = Get-Service -Name 'ollama' -ErrorAction SilentlyContinue
    $proc = Get-Process -Name 'ollama' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (($svc -and $svc.Status -eq 'Running') -or $proc) {
        Set-ServiceStatus 'Ollama' 'Running'
        if ($proc) {
            $ram = "$([math]::Round($proc.WorkingSet64/1MB, 0)) MB"
            (ctrl 'OllamaResources').Text = "$ram RAM"
        }
    } else {
        Set-ServiceStatus 'Ollama' 'Stopped'
        (ctrl 'OllamaResources').Text = "— / —"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# NAT port remap helper
# ─────────────────────────────────────────────────────────────────────────────
function Set-NATPort([string]$Proto, [int]$OldExternal, [int]$NewExternal, [string]$InternalIP, [int]$InternalPort) {
    try {
        # Remove-NetNatStaticMapping requires piping from Get-NetNatStaticMapping —
        # it does not accept -ExternalPort / -Protocol as direct filter params
        Get-NetNatStaticMapping -NatName $cfg.NATName -ErrorAction SilentlyContinue |
            Where-Object { $_.ExternalPort -eq $OldExternal -and $_.Protocol -eq $Proto } |
            Remove-NetNatStaticMapping -Confirm:$false -ErrorAction SilentlyContinue
        Add-NetNatStaticMapping -NatName $cfg.NATName -Protocol $Proto `
            -ExternalIPAddress '0.0.0.0' -ExternalPort $NewExternal `
            -InternalIPAddress $InternalIP -InternalPort $InternalPort
        Write-UILog "NAT rule updated: $Proto $OldExternal -> $NewExternal (-> ${InternalIP}:${InternalPort})"
        return $true
    } catch {
        Write-UILog "ERROR remapping NAT: $_"
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Button event handlers
# ─────────────────────────────────────────────────────────────────────────────

# GitLab Start
(ctrl 'GitLabStart').Add_Click({
    Write-UILog "Starting GitLabVM..."
    Set-ServiceStatus 'GitLab' 'Starting'
    try { Start-VM -Name 'GitLabVM'; Write-UILog "GitLabVM started." }
    catch { Write-UILog "ERROR: $_" }
})

# GitLab Stop
(ctrl 'GitLabStop').Add_Click({
    Write-UILog "Stopping GitLabVM..."
    try { Stop-VM -Name 'GitLabVM' -Force; Write-UILog "GitLabVM stopped." }
    catch { Write-UILog "ERROR: $_" }
})

# GitLab Apply Port
(ctrl 'GitLabPort').Add_Click({
    $newWeb = [int](ctrl 'GitLabWebPortBox').Text
    $newSSH = [int](ctrl 'GitLabSSHPortBox').Text
    $ok = (Set-NATPort TCP $cfg.GitLabWebPort $newWeb $cfg.GitLabVMIP 80) -and
          (Set-NATPort TCP $cfg.GitLabSSHPort $newSSH $cfg.GitLabVMIP 22)
    if ($ok) {
        Set-ConfigValue 'GitLabWebPort' $newWeb
        Set-ConfigValue 'GitLabSSHPort' $newSSH
        $script:cfg = Get-Config
        (ctrl 'FooterGitLab').Text = "http://localhost:$newWeb"
    }
})

# Mattermost Start
(ctrl 'MattermostStart').Add_Click({
    Write-UILog "Starting MattermostVM..."
    Set-ServiceStatus 'Mattermost' 'Starting'
    try { Start-VM -Name 'MattermostVM'; Write-UILog "MattermostVM started." }
    catch { Write-UILog "ERROR: $_" }
})

# Mattermost Stop
(ctrl 'MattermostStop').Add_Click({
    Write-UILog "Stopping MattermostVM..."
    try { Stop-VM -Name 'MattermostVM' -Force; Write-UILog "MattermostVM stopped." }
    catch { Write-UILog "ERROR: $_" }
})

# Mattermost Apply Port
(ctrl 'MattermostPort').Add_Click({
    $newPort = [int](ctrl 'MattermostPortBox').Text
    $ok = Set-NATPort TCP $cfg.MattermostPort $newPort $cfg.MattermostVMIP 8065
    if ($ok) {
        Set-ConfigValue 'MattermostPort' $newPort
        $script:cfg = Get-Config
        (ctrl 'FooterMattermost').Text = "http://localhost:$newPort"
    }
})

# Ollama Start
(ctrl 'OllamaStart').Add_Click({
    Write-UILog "Starting Ollama service..."
    try {
        $svc = Get-Service -Name 'ollama' -ErrorAction SilentlyContinue
        if ($svc) { Start-Service 'ollama' }
        else { Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden }
        Write-UILog "Ollama started."
    } catch { Write-UILog "ERROR starting Ollama: $_" }
})

# Ollama Stop
(ctrl 'OllamaStop').Add_Click({
    Write-UILog "Stopping Ollama..."
    try {
        $svc = Get-Service -Name 'ollama' -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { Stop-Service 'ollama' -Force }
        Get-Process 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force
        Write-UILog "Ollama stopped."
    } catch { Write-UILog "ERROR stopping Ollama: $_" }
})

# Ollama Apply Port (sets env var OLLAMA_HOST for next start)
(ctrl 'OllamaPort').Add_Click({
    $newPort = [int](ctrl 'OllamaPortBox').Text
    [System.Environment]::SetEnvironmentVariable('OLLAMA_HOST', "0.0.0.0:$newPort", 'Machine')
    Set-ConfigValue 'OllamaPort' $newPort
    $script:cfg = Get-Config
    (ctrl 'FooterOllama').Text = "http://localhost:$newPort"
    Write-UILog "Ollama port set to $newPort (restart Ollama to apply)."
})

# ─────────────────────────────────────────────────────────────────────────────
# 5-second refresh timer
# ─────────────────────────────────────────────────────────────────────────────
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({ Refresh-Stats })
$timer.Start()

# Initial refresh
Refresh-Stats
Write-UILog "Monitor started. Polling every 5 seconds."

# ─────────────────────────────────────────────────────────────────────────────
# Show window
# ─────────────────────────────────────────────────────────────────────────────
$null = $window.ShowDialog()
$timer.Stop()
