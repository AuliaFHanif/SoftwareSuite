#!/usr/bin/env bash
# =============================================================================
# prepare-golden-image.sh
# Run this as ROOT inside a fresh Ubuntu 24.04 LTS VM.
# Choose which role to install via the ROLE env var:
#
#   sudo ROLE=gitlab      ./prepare-golden-image.sh
#   sudo ROLE=mattermost  ./prepare-golden-image.sh
#
# After the script finishes, the VM shuts down automatically.
# Export the resulting VHDX from Hyper-V Manager.
# =============================================================================

set -euo pipefail

ROLE="${ROLE:-}"
if [[ -z "$ROLE" ]]; then
    echo "ERROR: Set ROLE=gitlab or ROLE=mattermost before running."
    exit 1
fi

log() { echo -e "\033[1;34m[$(date +%H:%M:%S)] $*\033[0m"; }
err() { echo -e "\033[1;31m[$(date +%H:%M:%S)] ERROR: $*\033[0m" >&2; exit 1; }

# ─── Common hardening ────────────────────────────────────────────────────────
common_setup() {
    log "Updating system packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get install -y -qq curl wget gnupg2 ca-certificates tzdata ufw

    log "Configuring firewall..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp comment 'SSH'

    log "Configuring static IP via netplan..."
    # The IP must match what Setup-HyperV.ps1 expects
    local static_ip
    if [[ "$ROLE" == "gitlab" ]]; then
        static_ip="192.168.100.10"
    elif [[ "$ROLE" == "nextjs" ]]; then
        static_ip="192.168.100.12"
    else
        static_ip="192.168.100.11"
    fi

    # Ubuntu 24.04 on Hyper-V Gen2 typically names the NIC 'eth0' or 'enp3s0'
    # This netplan config uses a match on the MAC type to cover both names.
    # Remove the installer's default DHCP config first to prevent conflicts.
    rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml
    cat > /etc/netplan/99-static.yaml <<NETPLAN
network:
  version: 2
  ethernets:
    id0:
      match:
        name: "eth*"
      dhcp4: false
      addresses: ["${static_ip}/24"]
      routes:
        - to: default
          via: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
NETPLAN
    chmod 600 /etc/netplan/99-static.yaml
    netplan apply || true

    log "Common setup done."
}

# ─── GitLab CE ───────────────────────────────────────────────────────────────
install_gitlab() {
    log "Installing GitLab CE (Omnibus) on Ubuntu 24.04 LTS..."
    ufw allow 80/tcp  comment 'GitLab HTTP'
    ufw allow 443/tcp comment 'GitLab HTTPS'
    ufw --force enable

    # Official GitLab CE repo script — supports Noble (24.04)
    curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
    EXTERNAL_URL="http://192.168.100.10" apt-get install -y gitlab-ce

    log "Running initial gitlab-ctl reconfigure (takes a few minutes)..."
    gitlab-ctl reconfigure

    log "Creating default admin token for API access..."
    gitlab-rails runner "
    user = User.find_by(username: 'root')
    token = user.personal_access_tokens.create(
        name: 'initial-admin-token',
        scopes: ['api', 'read_user', 'read_repository', 'write_repository'],
        expires_at: 10.years.from_now
    )
    puts \"root PAT: #{token.token}\"
    " 2>&1 | tee /root/gitlab-initial-token.txt || true

    log "Enabling GitLab auto-start on boot..."
    systemctl enable gitlab-runsvdir

    log "GitLab CE installation complete."
    log "  Web UI:  http://192.168.100.10"
    log "  SSH:     ssh://192.168.100.10:22"
    log "  Initial root password: /etc/gitlab/initial_root_password"
    log "  Admin token saved to: /root/gitlab-initial-token.txt"
}

# ─── Mattermost ──────────────────────────────────────────────────────────────
install_mattermost() {
    log "Installing Mattermost Team Edition on Ubuntu 24.04 LTS..."
    ufw allow 8065/tcp comment 'Mattermost'
    ufw --force enable

    # Install PostgreSQL 16 (default in Ubuntu 24.04)
    apt-get install -y postgresql postgresql-contrib

    systemctl enable --now postgresql

    log "Configuring PostgreSQL for Mattermost..."
    # Use runuser (not sudo-inside-root) for non-interactive postgres commands
    runuser -l postgres -c "psql -c \"CREATE USER mmuser WITH PASSWORD 'mmuser_password';\"" 2>/dev/null || true
    runuser -l postgres -c "psql -c \"CREATE DATABASE mattermost WITH ENCODING 'UTF8' OWNER mmuser;\"" 2>/dev/null || true
    runuser -l postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE mattermost TO mmuser;\"" 2>/dev/null || true

    log "Downloading Mattermost..."
    MM_VERSION="10.5.0"   # Update to latest stable before building — check https://mattermost.com/download/
    MM_ARCHIVE="mattermost-team-${MM_VERSION}-linux-amd64.tar.gz"
    wget -q "https://releases.mattermost.com/${MM_VERSION}/${MM_ARCHIVE}" -O /tmp/mattermost.tar.gz
    tar -xzf /tmp/mattermost.tar.gz -C /opt
    rm /tmp/mattermost.tar.gz

    useradd --system --no-create-home --shell /usr/sbin/nologin mattermost 2>/dev/null || true
    mkdir -p /opt/mattermost/data
    chown -R mattermost:mattermost /opt/mattermost
    chmod -R g+w /opt/mattermost

    log "Writing Mattermost config..."
    MM_CFG="/opt/mattermost/config/config.json"
    # Update the SQL driver and data source in the existing config.
    # Use \& to produce a literal & in sed output (& alone means 'matched string')
    sed -i 's|"DriverName": "mysql"|"DriverName": "postgres"|' "$MM_CFG"
    sed -i 's|"DataSource": ".*"|"DataSource": "postgres://mmuser:mmuser_password@localhost/mattermost?sslmode=disable\&connect_timeout=10"|' "$MM_CFG"

    # Set site URL to the VM's static IP
    sed -i 's|"SiteURL": ""|"SiteURL": "http://192.168.100.11:8065"|' "$MM_CFG"

    log "Installing Mattermost systemd service..."
    cat > /etc/systemd/system/mattermost.service <<'UNIT'
[Unit]
Description=Mattermost Team Edition
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=notify
ExecStart=/opt/mattermost/bin/mattermost
TimeoutStartSec=3600
Restart=always
RestartSec=10
WorkingDirectory=/opt/mattermost
User=mattermost
Group=mattermost
LimitNOFILE=49152

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable mattermost
    systemctl start mattermost

    log "Waiting for Mattermost to become ready..."
    for i in {1..30}; do
        if curl -sf http://localhost:8065/api/v4/system/ping > /dev/null 2>&1; then
            log "Mattermost is up!"
            break
        fi
        sleep 5
    done

    log "Mattermost installation complete."
    log "  Web UI: http://192.168.100.11:8065"
    log "  Complete setup at the web UI on first access."
}

# ─── Next.js ─────────────────────────────────────────────────────────────────
install_nextjs() {
    log "Installing Next.js App on Ubuntu 24.04 LTS..."
    ufw allow 3000/tcp comment 'Next.js HTTP'
    ufw --force enable

    log "Installing Node.js 22.x LTS..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs

    log "Installing PM2 for process management..."
    npm install -g pm2

    log "Setting up app directory..."
    mkdir -p /opt/nextjs-app
    if [[ -f "/root/nextjs-app.tar.gz" ]]; then
        log "Found nextjs-app.tar.gz, extracting..."
        tar -xzf /root/nextjs-app.tar.gz -C /opt/nextjs-app
        cd /opt/nextjs-app
        npm install --production
    else
        log "Warning: /root/nextjs-app.tar.gz not found. Initializing a fresh app."
        cd /opt
        npx -y create-next-app@latest nextjs-app --ts --app --src-dir --eslint --use-npm --no-tailwind
        cd /opt/nextjs-app
        npm run build
    fi

    log "Setting up environment variables..."
    echo "OLLAMA_URL=http://192.168.100.1:11434" > /opt/nextjs-app/.env.local

    log "Starting app with PM2..."
    pm2 start npm --name "nextjs-app" -- start
    pm2 save
    env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root

    log "Next.js installation complete."
    log "  Web UI: http://192.168.100.12:3000"
}

# ─── Cleanup before VHDX export ──────────────────────────────────────────────
cleanup_and_shutdown() {
    log "Cleaning up before export..."
    apt-get clean -qq
    apt-get autoremove -y -qq
    rm -rf /tmp/* /var/tmp/*
    # Zero free space for better VHDX compression
    dd if=/dev/zero of=/zero.fill bs=1M 2>/dev/null || true
    sync
    rm -f /zero.fill
    # Remove machine-id so each deployed copy gets a unique ID
    truncate -s0 /etc/machine-id
    rm -f /var/lib/dbus/machine-id
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
    # Clear SSH host keys — they'll regenerate on first boot
    rm -f /etc/ssh/ssh_host_*

    log "Shutdown in 5 seconds..."
    sleep 5
    shutdown -h now
}

# ─── Main ─────────────────────────────────────────────────────────────────────
log "=== AllInOne Golden Image Builder — ROLE=$ROLE ==="
common_setup
case "$ROLE" in
    gitlab)     install_gitlab     ;;
    mattermost) install_mattermost ;;
    nextjs)     install_nextjs     ;;
    *)          err "Unknown ROLE '$ROLE'. Use 'gitlab', 'mattermost', or 'nextjs'." ;;
esac
cleanup_and_shutdown
