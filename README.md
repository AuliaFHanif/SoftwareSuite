# AllInOne Installer — Air-Gapped Hyper-V Edition

## Overview

Deploys three services on any **Windows 10/11 Pro/Enterprise** machine with no internet access:

| Service | How | Address |
|---|---|---|
| **Ollama** | Native Windows install | `http://localhost:11434` |
| **GitLab CE** | Hyper-V VM (Ubuntu 24.04) | `http://localhost:8090` |
| **Mattermost** | Hyper-V VM (Ubuntu 24.04) | `http://localhost:8065` |

A dark WPF monitoring dashboard lets employees start/stop services, change ports, and watch resource usage.

---

## Prerequisites (target machines)

- Windows 10/11 **Pro, Enterprise, or Education** (Home does not support Hyper-V)
- Hardware virtualisation enabled in BIOS (Intel VT-x or AMD-V)
- At least **16 GB RAM** and **100 GB free disk space**
- Run the installer as **Administrator**

---

## Project Structure

```
AllInOneInstaller/
├── installer.iss                    Inno Setup script -> compile to AllInOneSetup.exe
├── README.md                        This file
├── scripts/
│   └── Setup-HyperV.ps1             Called by installer: Hyper-V, NAT, VMs
├── monitor/
│   ├── Monitor.ps1                  WPF monitoring dashboard
│   └── Uninstall-Services.ps1       Called by uninstaller to clean up VMs/NAT
└── payload/                         Large binaries you build once (see Phase 1)
    ├── OllamaSetup.exe              Download from https://ollama.com/download/windows
    ├── images/
    │   ├── GitLabVM.vhdx            Golden disk image (see Phase 1, Step 2)
    │   └── MattermostVM.vhdx        Golden disk image (see Phase 1, Step 3)
    └── prepare-golden-image.sh      Run inside Ubuntu VMs to bake the services
```

> **SVN tip:** `.vhdx` files are binary. Before committing run:
> `svn propset svn:mime-type application/octet-stream payload/images/*.vhdx`

---

## Phase 1 — Build the Payload (once, on an internet-connected machine)

This phase produces the three binary files that go into `payload/`. Do it once. After
that, every new project deployment just checks out SVN and runs the installer.

---

### Step 1 — Enable Hyper-V on your build machine

Open **PowerShell as Administrator** and run:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
Restart-Computer
```

After the reboot, open **Hyper-V Manager** (search for it in the Start menu) to confirm
it's installed.

---

### Step 2 — Build the GitLab golden VHDX

#### 2a. Download Ubuntu Server 24.04 LTS

Go to https://ubuntu.com/download/server and download the **Ubuntu Server 24.04 LTS** ISO.

#### 2b. Create a new VM in Hyper-V Manager

1. Open **Hyper-V Manager** → **Action** → **New** → **Virtual Machine**
2. Name: `GitLabVM-Build`
3. Generation: **Generation 2**
4. Startup memory: `4096 MB` (uncheck dynamic memory)
5. Networking: connect to **Default Switch** (for internet during build)
6. Virtual Hard Disk: create new, **80 GB**
7. Installation: choose the Ubuntu ISO you downloaded
8. Click **Finish**

Before starting, disable Secure Boot for the Ubuntu installer:
- Right-click `GitLabVM-Build` → **Settings** → **Security**
- Change **Secure Boot template** to `Microsoft UEFI Certificate Authority`
- Click **OK**

#### 2c. Install Ubuntu (minimal)

1. Start the VM, connect to its console
2. Complete the Ubuntu installer:
   - Language: English
   - Storage: use entire disk (default)
   - Profile: set any username/password (e.g. `admin` / `admin`)
   - **Enable OpenSSH server** when prompted
   - Skip all optional snaps
3. Reboot when prompted, then eject the ISO via **Media** → **DVD Drive** → **Eject**

#### 2d. Copy and run the golden-image script

From your Windows host, open PowerShell and copy the script into the VM.
First get the VM's IP: in the VM console run `ip a` and note the `eth0` IP.

```powershell
# Replace 172.x.x.x with your VM's actual IP
scp .\payload\prepare-golden-image.sh admin@172.x.x.x:~/
```

Then SSH in and run it:

```bash
ssh admin@172.x.x.x
chmod +x prepare-golden-image.sh
sudo ROLE=gitlab ./prepare-golden-image.sh
```

The script takes **10-20 minutes**. It installs GitLab CE, runs `gitlab-ctl reconfigure`,
sets the static IP, hardens the system, and shuts down automatically.

#### 2e. Export the VHDX

After the VM shuts down:

```powershell
# Find where Hyper-V stored the disk (adjust path if needed)
$vhdx = (Get-VM -Name 'GitLabVM-Build' | Get-VMHardDiskDrive).Path
Copy-Item $vhdx ".\payload\images\GitLabVM.vhdx"
```

> The copy may take several minutes for an 80 GB disk.

---

### Step 3 — Build the Mattermost golden VHDX

Repeat Step 2 with these differences:

| Setting | Value |
|---|---|
| VM name | `MattermostVM-Build` |
| Disk size | `40 GB` (Mattermost is much smaller) |
| Script command | `sudo ROLE=mattermost ./prepare-golden-image.sh` |
| Output file | `payload\images\MattermostVM.vhdx` |

```powershell
# After VM shuts down:
$vhdx = (Get-VM -Name 'MattermostVM-Build' | Get-VMHardDiskDrive).Path
Copy-Item $vhdx ".\payload\images\MattermostVM.vhdx"
```

---

### Step 4 — Download Ollama

Download the Windows installer from https://ollama.com/download/windows and save it as:

```
payload\OllamaSetup.exe
```

---

### Step 5 — Compile the installer

1. Download and install **Inno Setup 6** from https://jrsoftware.org/isdl.php
2. Open `installer.iss` in Inno Setup IDE
3. Press **F9** (or **Build** → **Compile**)
4. Output: `Output\AllInOneSetup.exe`

---

### Step 6 — Commit everything to SVN

```bash
svn add payload/images/GitLabVM.vhdx
svn add payload/images/MattermostVM.vhdx
svn add payload/OllamaSetup.exe
svn add Output/AllInOneSetup.exe
svn propset svn:mime-type application/octet-stream payload/images/GitLabVM.vhdx
svn propset svn:mime-type application/octet-stream payload/images/MattermostVM.vhdx
svn propset svn:mime-type application/octet-stream payload/OllamaSetup.exe
svn propset svn:mime-type application/octet-stream Output/AllInOneSetup.exe
svn commit -m "Add AllInOne installer payload and compiled setup"
```

---

## Phase 2 — Deploy on a New Project Machine

This is what every new project deployment looks like. No internet required.

---

### Step 1 — Check out from SVN

```bash
svn checkout svn://your-svn-server/AllInOneInstaller C:\AllInOneInstaller
```

---

### Step 2 — Run the installer

1. Open `C:\AllInOneInstaller\Output\AllInOneSetup.exe`
2. Right-click → **Run as Administrator**
3. Follow the wizard (click Next through the pages)

**What happens automatically:**

| Stage | Action |
|---|---|
| Files | VHDXs copied to `C:\ProgramData\AllInOneDevStack\VMs\` |
| Hyper-V | Enables the Hyper-V Windows feature (may trigger reboot) |
| Network | Creates `AllInOneSwitch` (internal) + Windows NAT `192.168.100.0/24` |
| VMs | Creates `GitLabVM` and `MattermostVM` from the golden VHDXs |
| NAT rules | Maps host ports to VM internal ports |
| Ollama | Installs Ollama natively on the Windows host |
| VMs boot | Both VMs are started automatically |
| Shortcut | "AllInOne Monitor" shortcut added to Desktop and Start Menu |

> **If a reboot happens:** The installer will automatically restart itself after the reboot
> and continue from where it left off. Log in as Administrator after the reboot.

---

### Step 3 — Wait for services to become ready

After the installer finishes:

| Service | Ready after | Sign it's ready |
|---|---|---|
| Ollama | ~30 seconds | `http://localhost:11434` returns `Ollama is running` |
| GitLab | ~3-5 minutes | `http://localhost:8090` loads the sign-in page |
| Mattermost | ~1-2 minutes | `http://localhost:8065` loads the setup wizard |

GitLab runs `gitlab-ctl reconfigure` on first boot which takes a few minutes — this is normal.

---

### Step 4 — First-time service setup

#### GitLab

1. Open `http://localhost:8090` in a browser
2. Sign in with username `root`
3. The initial root password is in the VM at `/etc/gitlab/initial_root_password`
   (valid for 24 hours after first boot):
   ```powershell
   # Read it via Hyper-V integration services (if available), or SSH in:
   ssh admin@192.168.100.10
   sudo cat /etc/gitlab/initial_root_password
   ```
4. Change the root password immediately after first login
5. Create your project group and repositories

#### Mattermost

1. Open `http://localhost:8065` in a browser
2. Complete the setup wizard (create admin account, team name, etc.)
3. Mattermost is ready to use

#### Ollama

```powershell
# Test Ollama is running
Invoke-RestMethod http://localhost:11434

# Pull a model (requires internet — do this during setup, before going air-gapped)
ollama pull llama3.2

# Or copy a model from another machine that already has it:
# On source: ollama show --modelfile llama3.2 > modelfile.txt
# On target: copy model files to C:\Users\<user>\.ollama\models\
```

---

## Using the Monitoring Dashboard

Launch from the **"AllInOne Monitor"** Desktop shortcut (auto-elevates to Admin).

| Feature | How to use |
|---|---|
| **Start / Stop** | Click the green ▶ Start or red ■ Stop button next to each service |
| **Status LED** | Green = running, Orange = starting, Red = stopped |
| **CPU / RAM** | Updates every 5 seconds via Hyper-V metrics |
| **Change port** | Type a new port number, click **↔ Apply Port** |
| **Activity log** | Bottom panel shows timestamped actions and errors |
| **Quick links** | Footer shows clickable URLs for each service |

---

## Default Port Mappings

| Service | Host Port | Internal Port |
|---|---|---|
| GitLab Web | **8090** | 80 (inside VM) |
| GitLab SSH | **2222** | 22 (inside VM) |
| Mattermost | **8065** | 8065 (inside VM) |
| Ollama API | **11434** | native (no VM) |

All ports can be changed post-install via the monitoring dashboard without restarting VMs.

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| "Hyper-V cannot be enabled" | BIOS virtualisation off | Enter BIOS, enable Intel VT-x or AMD-V |
| VM won't start after reboot | Automatic start didn't run | Open monitor as Admin, click ▶ Start |
| GitLab 502 Bad Gateway | Still starting up | Wait 3-5 minutes, refresh |
| GitLab 502 persists | Startup issue | SSH into VM: `sudo gitlab-ctl status` |
| Mattermost blank page | Still starting | Wait 1-2 minutes, refresh |
| Port already in use | Conflict with existing app | Use monitor to remap to another port |
| Monitor shows "VM not found" | Hyper-V module not loaded | Run monitor as Administrator |
| VHDX locked in SVN | Missing binary property | Run `svn propset svn:mime-type application/octet-stream` on the file |

---

## Uninstalling

Run **Add/Remove Programs** → **AllInOne DevStack** → **Uninstall**.

This will:
- Stop and delete both Hyper-V VMs
- Remove the NAT and virtual switch
- Remove all installed files and registry keys
- Leave the VHDX backups in place (delete manually if desired)
