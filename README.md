# RHOS-VAF Dev-Tools

Automated deployment toolkit for Single Node OpenShift (SNO) and Red Hat OpenStack Services on OpenShift (RHOSO).

## Quick Start

### 1. Configure Deployment

```bash
cp configs/sno.example.sh configs/sno.local.sh
vi configs/sno.local.sh  # Set BMC host, network, and cluster details
source configs/sno.local.sh
```

### 2. Deploy Single Node OpenShift

```bash
make validate_config  # Verify configuration
make deploy_sno       # Deploy SNO cluster
```

### 3. Deploy RHOSO

```bash
# Install prerequisites
make install_lvm_operator              # LVM Storage for persistent volumes
make install_gitops_operator           # OpenShift GitOps (ArgoCD)
make enable_argocd                     # Enable ArgoCD with OpenStack health checks
make configure_openshift_gitops        # Configure ArgoCD permissions and TLS

# Deploy OpenStack infrastructure
make deploy_openstack_dependencies     # Cert-manager, MetalLB, NMState
make deploy_openstack_operator         # OpenStack operator
make deploy_openstack_operator_cr      # OpenStack operator CR (bootstrap services)
make deploy_vault_secrets_operator     # Vault Secrets Operator

# Configure Vault authentication
make configure_vault_authentication    # AppRole for OpenStack namespace
```

## Configuration

See `configs/sno.example.sh` for all available options.

**Essential variables:**
- `SNO_BMC_HOST` - iDRAC hostname or IP
- `SNO_NODE_MAC` - Provisioning interface MAC address
- `SNO_NODE_IP` - IP address for the node
- `SNO_NODE_IFACE` - Network interface name
- `SNO_OPENSHIFT_VERSION` - Full version (e.g., 4.18.41)

**Vault credentials** are auto-fetched from Vault if `VAULT_BMC_SECRET_PATH` and `VAULT_APPROLE_PATH` are set.

## Documentation

Run `make help` for full command reference.
