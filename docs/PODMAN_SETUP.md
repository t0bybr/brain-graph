# Podman Setup für Fedora Silverblue

## Prerequisites

```bash
# Podman ist bereits installiert in Silverblue!
podman --version

# Installiere podman-compose
pip3 install --user podman-compose

# Optional: podman-docker (Docker CLI Kompatibilität)
rpm-ostree install podman-docker

# Nach ostree install:
systemctl reboot
```

## Podman Socket Setup

```bash
# Enable Podman socket für rootless
systemctl --user enable --now podman.socket

# Verify
systemctl --user status podman.socket

# Get socket path
echo $XDG_RUNTIME_DIR/podman/podman.sock
# Usually: /run/user/1000/podman/podman.sock
```

## SELinux Configuration

```bash
# Allow containers to access host files
sudo setsebool -P container_manage_cgroup on

# For shared volumes
sudo chcon -R -t container_file_t ./storage
sudo chcon -R -t container_file_t ./docker/postgres
```

## Podman Network Setup

```bash
# Create networks
podman network create brain_graph_network
podman network create traefik_public

# List networks
podman network ls
```

## GPU Access (for encoders)

```bash
# Install nvidia-container-toolkit (if you have NVIDIA GPU)
# Note: This requires layering on Silverblue
rpm-ostree install nvidia-container-toolkit
systemctl reboot

# Test GPU access
podman run --rm --device nvidia.com/gpu=all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

## Podman mkcert Setup

```bash
# mkcert installieren (am besten über Homebrew/Linuxbrew)
# Option 1: via Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install mkcert nss

# Option 2: Manuell
mkdir -p ~/.local/bin
cd ~/.local/bin
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
chmod +x mkcert-v*-linux-amd64
mv mkcert-v*-linux-amd64 mkcert

# NSS tools (optional, für Firefox)
sudo rpm-ostree install nss-tools
systemctl reboot  # Nach ostree install erforderlich
```
