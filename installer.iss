; =============================================================================
; AllInOne Installer — Air-Gapped Hyper-V Edition
; Deploys: Ollama (native), GitLab CE (Hyper-V VM), Mattermost (Hyper-V VM)
; Requires: Windows 10/11 Pro/Enterprise, hardware virtualisation enabled
; =============================================================================

#define MyAppName    "AllInOne DevStack"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "YourCompany IT"
#define InstallDir   "{autopf}\AllInOneDevStack"
#define VHDXDest     "{commonappdata}\AllInOneDevStack\VMs"
#define MonitorDest  "{commonappdata}\AllInOneDevStack\Monitor"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={#InstallDir}
DefaultGroupName={#MyAppName}
OutputBaseFilename=AllInOneSetup
Compression=lzma2/ultra64
SolidCompression=yes
; Require elevation — Hyper-V and NAT operations need admin
PrivilegesRequired=admin
; Allow reboot for Hyper-V feature enablement
RestartIfNeededByRun=yes
; Show a nicer wizard
WizardStyle=modern
; After reboot, the installer resumes from a flag file
SetupMutex=AllInOneSetup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
english.CheckingHyperV=Checking Hyper-V status...
english.EnablingHyperV=Enabling Hyper-V (a reboot may follow)...
english.CopyingVHDX=Copying VM disk images (this may take several minutes)...
english.CreatingVMs=Creating Hyper-V virtual machines...
english.ConfiguringNAT=Configuring internal network and NAT rules...
english.InstallingOllama=Installing Ollama...
english.InstallingMonitor=Installing monitoring dashboard...
english.Done=All services installed successfully.

; =============================================================================
; Files to bundle
; =============================================================================
[Files]
; Ollama native installer
Source: "payload\OllamaSetup.exe";           DestDir: "{tmp}";                   Flags: deleteafterinstall
; Golden VM disk images — large files, copied to a permanent location
Source: "payload\images\GitLabVM.vhdx";      DestDir: "{commonappdata}\AllInOneDevStack\VMs"; Flags: ignoreversion
Source: "payload\images\MattermostVM.vhdx";  DestDir: "{commonappdata}\AllInOneDevStack\VMs"; Flags: ignoreversion
; PowerShell helper scripts
Source: "scripts\Setup-HyperV.ps1";          DestDir: "{tmp}";                   Flags: deleteafterinstall
; Monitoring dashboard — kept permanently
Source: "monitor\Monitor.ps1";               DestDir: "{commonappdata}\AllInOneDevStack\Monitor"; Flags: ignoreversion
Source: "monitor\Monitor.ps1.manifest";      DestDir: "{commonappdata}\AllInOneDevStack\Monitor"; Flags: ignoreversion skipifsourcedoesntexist
Source: "monitor\Uninstall-Services.ps1";    DestDir: "{commonappdata}\AllInOneDevStack\Monitor"; Flags: ignoreversion

; =============================================================================
; Run steps — order matters
; =============================================================================
[Run]
; Step 1: Enable Hyper-V feature (triggers reboot if not already on)
Filename: "powershell.exe";
    Parameters: "-NonInteractive -ExecutionPolicy Bypass -File ""{tmp}\Setup-HyperV.ps1"" -Action EnableHyperV";
    StatusMsg: "{cm:EnablingHyperV}";
    Flags: runhidden waituntilterminated

; Step 2: Create internal switch + NAT
Filename: "powershell.exe";
    Parameters: "-NonInteractive -ExecutionPolicy Bypass -File ""{tmp}\Setup-HyperV.ps1"" -Action CreateNetwork";
    StatusMsg: "{cm:ConfiguringNAT}";
    Flags: runhidden waituntilterminated

; Step 3: Create VMs from the copied VHDXs
; NOTE: {commonappdata} is NOT expanded inside Parameters — Setup-HyperV.ps1
; defaults to $env:ProgramData\AllInOneDevStack\VMs which is the same path.
Filename: "powershell.exe";
    Parameters: "-NonInteractive -ExecutionPolicy Bypass -File ""{tmp}\Setup-HyperV.ps1"" -Action CreateVMs";
    StatusMsg: "{cm:CreatingVMs}";
    Flags: runhidden waituntilterminated

; Step 4: Configure NAT port-forwarding rules
Filename: "powershell.exe";
    Parameters: "-NonInteractive -ExecutionPolicy Bypass -File ""{tmp}\Setup-HyperV.ps1"" -Action ConfigureNAT";
    StatusMsg: "{cm:ConfiguringNAT}";
    Flags: runhidden waituntilterminated

; Step 5: Install Ollama silently
Filename: "{tmp}\OllamaSetup.exe";
    Parameters: "/VERYSILENT /NORESTART";
    StatusMsg: "{cm:InstallingOllama}";
    Flags: waituntilterminated

; Step 6: Start both VMs
Filename: "powershell.exe";
    Parameters: "-NonInteractive -ExecutionPolicy Bypass -Command ""Start-VM -Name GitLabVM; Start-VM -Name MattermostVM""";
    StatusMsg: "Starting virtual machines...";
    Flags: runhidden waituntilterminated

; Step 7: Offer to launch the monitor dashboard
Filename: "powershell.exe";
    Parameters: "-ExecutionPolicy Bypass -File ""{commonappdata}\AllInOneDevStack\Monitor\Monitor.ps1""";
    Description: "Launch AllInOne Monitor Dashboard";
    Flags: postinstall nowait skipifsilent

; =============================================================================
; Desktop shortcut for the monitor
; =============================================================================
[Icons]
Name: "{commondesktop}\AllInOne Monitor";
    Filename: "powershell.exe";
    Parameters: "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""{commonappdata}\AllInOneDevStack\Monitor\Monitor.ps1""";
    IconFilename: "{sys}\shell32.dll";
    IconIndex: 238;
    Comment: "Open the AllInOne service monitoring dashboard";
    Flags: uninsneveruninstall

Name: "{group}\AllInOne Monitor";
    Filename: "powershell.exe";
    Parameters: "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""{commonappdata}\AllInOneDevStack\Monitor\Monitor.ps1""";
    IconFilename: "{sys}\shell32.dll";
    IconIndex: 238

; =============================================================================
; Registry — store config so the monitor can read defaults
; =============================================================================
[Registry]
Root: HKLM; Subkey: "SOFTWARE\AllInOneDevStack"; ValueType: string; ValueName: "InstallDir";       ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\AllInOneDevStack"; ValueType: string; ValueName: "MonitorDir";       ValueData: "{commonappdata}\AllInOneDevStack\Monitor"
Root: HKLM; Subkey: "SOFTWARE\AllInOneDevStack"; ValueType: dword;  ValueName: "GitLabWebPort";    ValueData: "8090"
Root: HKLM; Subkey: "SOFTWARE\AllInOneDevStack"; ValueType: dword;  ValueName: "GitLabSSHPort";    ValueData: "2222"
Root: HKLM; Subkey: "SOFTWARE\AllInOneDevStack"; ValueType: dword;  ValueName: "MattermostPort";   ValueData: "8065"
Root: HKLM; Subkey: "SOFTWARE\AllInOneDevStack"; ValueType: dword;  ValueName: "OllamaPort";       ValueData: "11434"
Root: HKLM; Subkey: "SOFTWARE\AllInOneDevStack"; ValueType: string; ValueName: "GitLabVMIP";       ValueData: "192.168.100.10"
Root: HKLM; Subkey: "SOFTWARE\AllInOneDevStack"; ValueType: string; ValueName: "MattermostVMIP";   ValueData: "192.168.100.11"

; =============================================================================
; Uninstall — stop and remove VMs, remove NAT
; Uses a dedicated cleanup script to avoid quote-escaping issues with -Command
; =============================================================================
[UninstallRun]
Filename: "powershell.exe";
    Parameters: "-NonInteractive -ExecutionPolicy Bypass -File ""{commonappdata}\AllInOneDevStack\Monitor\Uninstall-Services.ps1""";
    Flags: runhidden waituntilterminated

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\AllInOneDevStack"
