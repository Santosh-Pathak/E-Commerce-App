#!/bin/bash
# Install GitHub Actions self-hosted runner on Ubuntu (EC2 / bastion).
# Prerequisites: Docker, Trivy, git (see terraform/install_tools.sh)
#
# Usage:
#   1. GitHub → Repo → Settings → Actions → Runners → New self-hosted runner → Linux
#   2. Copy the registration token from the page
#   3. Run: sudo ./scripts/setup-github-runner.sh <REGISTRATION_TOKEN>
#
# Optional env:
#   RUNNER_NAME=easyshop-ec2  (default: hostname)
#   RUNNER_LABELS=easyshop,linux  (default; workflow expects label: easyshop)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <GITHUB_REGISTRATION_TOKEN>"
  echo "Get token from: Settings → Actions → Runners → New self-hosted runner"
  exit 1
fi

REGISTRATION_TOKEN="$1"
REPO_URL="https://github.com/Santosh-Pathak/E-Commerce-App"
RUNNER_VERSION="2.321.0"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-easyshop,linux}"
INSTALL_DIR="/opt/actions-runner"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 <token>"
  exit 1
fi

apt-get update -y
apt-get install -y curl jq libicu-dev

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

if [[ ! -f ./config.sh ]]; then
  curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
  rm -f actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
fi

# Register (re-run after removing _work if re-registering)
if [[ -f .runner ]]; then
  echo "Runner already configured in ${INSTALL_DIR}. To re-register: ./config.sh remove then re-run this script."
  exit 0
fi

./config.sh \
  --url "${REPO_URL}" \
  --token "${REGISTRATION_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --unattended \
  --replace

# Install and start as a service (runs on boot)
./svc.sh install
./svc.sh start
./svc.sh status

# Allow runner user to use Docker (service runs as specific user — often the user who installed)
RUNNER_USER="$(stat -c '%U' "${INSTALL_DIR}")"
usermod -aG docker "${RUNNER_USER}" 2>/dev/null || true

echo ""
echo "Self-hosted runner installed."
echo "  Name:   ${RUNNER_NAME}"
echo "  Labels: self-hosted,linux,x64,${RUNNER_LABELS}"
echo "  Verify: GitHub → Settings → Actions → Runners (should show Idle)"
