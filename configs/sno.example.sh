#!/bin/bash
# Example SNO Configuration File
#
# This is the AUTHORITATIVE source for configuration defaults and documentation.
# The Makefile has minimal fallback defaults for convenience, but this file
# documents all available options and their recommended values.
#
# Usage:
#   1. Copy this file: cp configs/sno.example.sh configs/sno.local.sh
#   2. Edit sno.local.sh with your values
#   3. Source it: source configs/sno.local.sh
#   4. Deploy: make deploy_sno

# ============================================================================
# REQUIRED CONFIGURATION - YOU MUST SET THESE
# ============================================================================

# BMC/iDRAC Configuration
export SNO_BMC_HOST="idrac.example.com"        # Your iDRAC hostname or IP

# BMC Credentials (optional - will auto-fetch from Vault if not set)
# Option 1: Set directly (not recommended for security)
# export SNO_BMC_USERNAME="root"
# export SNO_BMC_PASSWORD="your_password"
#
# Option 2: Leave unset and let Makefile fetch from Vault automatically
# export VAULT_BMC_SECRET_PATH="your/vault/path/to/bmc-secret"

# Node Network Configuration
export SNO_NODE_MAC="b0:7b:25:xx:yy:zz"        # MAC address of provisioning interface
export SNO_NODE_IP="192.168.10.50"             # IP address to assign to the node
export SNO_NODE_IFACE="eno12399np0"            # RHCOS network interface name

# ============================================================================
# OPTIONAL CONFIGURATION - Customize as needed
# ============================================================================

# Cluster Configuration
export SNO_CLUSTER_NAME="ocp"
export SNO_BASE_DOMAIN="example.com"
export SNO_OPENSHIFT_VERSION="4.18.3"

# Network Configuration
export SNO_MACHINE_NETWORK="192.168.10.0/24"

# Node Hardware
export SNO_ROOT_DEVICE="/dev/sda"              # Or /dev/nvme0n1, etc.

# LVM Storage Configuration (optional - for post-install LVM Storage Operator)
# export SNO_LVM_DEVICE="/dev/sdb"             # Disk for LVM Storage Operator
# export SNO_LVM_DEVICE_CLASS="openstack"      # StorageClass name will be: lvms-openstack

# Secrets Paths
export PULL_SECRET="/path/to/pull-secret"
export BMC_CREDENTIALS_FILE="/path/to/idrac_access.yaml"

# ============================================================================
# ADVANCED OPTIONS (uncomment to use)
# ============================================================================

# Alternative: Use specific release image instead of version
# export SNO_RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:4.18.3-x86_64"

# ISO HTTP server port
# export SNO_ISO_HTTP_PORT="80"

# Installation timeout (in seconds)
# export SNO_INSTALLER_TIMEOUT="7200"

# Enable USB boot in BIOS (if VirtualMedia needs it)
# export SNO_ENABLE_USB_BOOT="true"

# Manually specify UEFI device path for VirtualMedia
# export SNO_VMEDIA_UEFI_PATH="PciRoot(0x0)/Pci(0x14,0x0)/USB(0x13,0x0)"

# Set core user password (post-install)
# export SNO_CORE_PASSWORD="your_password"

# Enable debug mode during installation
# export SNO_LIVE_DEBUG="true"

# Disable specific network interfaces during install
# export SNO_DISABLED_IFACES="ens1f0,ens1f1"

# ============================================================================
# ENVIRONMENT PRESETS (uncomment one if applicable)
# ============================================================================

# # Lab Environment Example
# export SNO_BASE_DOMAIN="lab.example.com"
# export SNO_MACHINE_NETWORK="192.168.10.0/24"

# # Development Environment
# export SNO_CLUSTER_NAME="ocp-dev"
# export SNO_BASE_DOMAIN="dev.example.com"
# export SNO_LIVE_DEBUG="true"

# ============================================================================
# POST-SOURCE MESSAGE
# ============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "ERROR: This script must be sourced, not executed"
    echo "Usage: source ${BASH_SOURCE[0]}"
    exit 1
fi

echo "✅ SNO configuration loaded from: ${BASH_SOURCE[0]}"
echo ""
echo "Configuration summary:"
echo "  Cluster: ${SNO_CLUSTER_NAME}.${SNO_BASE_DOMAIN}"
echo "  BMC Host: ${SNO_BMC_HOST}"
echo "  Node IP: ${SNO_NODE_IP}"
echo "  Node MAC: ${SNO_NODE_MAC}"
echo ""
echo "To validate: make validate_config"
echo "To deploy: make deploy_sno"
echo ""
