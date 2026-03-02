#!/bin/bash
# Post-create setup script for Copilot devcontainer
set -e

echo "=== Post-Create Setup Starting ==="

# Fix permissions for command history volume
# Docker volumes are created with root ownership, but we run as 'node' user
if [ -d /commandhistory ]; then
  sudo chown -R node:node /commandhistory
  touch /commandhistory/.zsh_history
  touch /commandhistory/.bash_history
fi

# Configure Terraform credentials for HCP Terraform
echo "Configuring Terraform credentials..."
mkdir -p ~/.terraform.d
cat > ~/.terraform.d/credentials.tfrc.json << EOF
{
  "credentials": {
    "app.terraform.io": {
      "token": "${TFE_TOKEN}"
    }
  }
}
EOF
echo "Terraform credentials configured"

# Install Terraform Agentic Workflows kit for Copilot
# Downloads the latest copilot release tarball and extracts into the project
KIT_REPO="hashi-demo-lab/terraform-agentic-workflows"
KIT_PATTERN="copilot-*.tar.gz"

echo "Installing Terraform Agentic Workflows kit..."
if gh release download \
  --repo "$KIT_REPO" \
  --pattern "$KIT_PATTERN" \
  --dir /tmp \
  --clobber 2>/dev/null; then

  TARBALL=$(ls /tmp/${KIT_PATTERN} 2>/dev/null | head -1)
  if [ -n "$TARBALL" ]; then
    tar xzf "$TARBALL" -C /workspace
    rm -f "$TARBALL"
    echo "Kit installed from $(basename "$TARBALL")"
  else
    echo "Warning: tarball not found after download"
  fi
else
  echo "Warning: could not download kit release (gh auth may be missing)"
fi

echo "=== Post-Create Setup Complete ==="
