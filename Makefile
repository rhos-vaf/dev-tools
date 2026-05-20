# Makefile for SNO (Single Node OpenShift) Installation
# Uses ci-framework bm_sno role from https://github.com/openstack-k8s-operators/ci-framework

# ============================================================================
# CONFIGURATION FILES
# ============================================================================
# Configuration can be provided via:
# 1. Shell config file: Copy configs/sno.example.sh to configs/sno.local.sh,
#    customize it, then: source configs/sno.local.sh && make deploy_sno
# 2. Environment variables: export SNO_BMC_HOST=... && make deploy_sno
# 3. Command-line parameters: make deploy_sno SNO_BMC_HOST=...
# 4. Editing the default values below (not recommended)

# ============================================================================
# CONFIGURATION VARIABLES
# ============================================================================
# ALL configuration values must be provided via:
# 1. Sourced config file (recommended): source configs/sno.local.sh
# 2. Environment variables: export SNO_BMC_HOST=...
# 3. Command-line: make deploy_sno SNO_BMC_HOST=...
#
# ALL defaults are defined in: configs/sno.example.sh (SINGLE SOURCE OF TRUTH)
# This Makefile contains NO defaults to avoid duplication/confusion.

# User configuration variables (accept from environment only, no defaults)
SNO_CLUSTER_NAME ?=
SNO_BASE_DOMAIN ?=
SNO_OPENSHIFT_VERSION ?=
SNO_MACHINE_NETWORK ?=
SNO_NODE_IP ?=
SNO_NODE_IFACE ?=
SNO_BMC_HOST ?=
SNO_NODE_MAC ?=
SNO_ROOT_DEVICE ?=
SNO_RELEASE_IMAGE ?=
SNO_ISO_HTTP_PORT ?=
SNO_CONTROLLER_IP ?=
SNO_INSTALLER_TIMEOUT ?=
SNO_ENABLE_USB_BOOT ?=
SNO_VMEDIA_UEFI_PATH ?=
SNO_CORE_PASSWORD ?=
SNO_LIVE_DEBUG ?=
SNO_DISABLED_IFACES ?=
PULL_SECRET ?=
BMC_CREDENTIALS_FILE ?=

# LVM Storage Configuration
SNO_LVM_DEVICE ?=
SNO_LVM_DEVICE_CLASS ?= openstack

# GitOps Configuration
GITOPS_REPO ?= https://github.com/openstack-k8s-operators/gitops.git
GITOPS_DIR ?= out/gitops

# GitOps Tools Configuration
GITOPS_TOOLS_REPO ?= https://github.com/rhos-vaf/gitops-tools.git
GITOPS_TOOLS_DIR ?= out/gitops-tools

# BMC Credentials - can be provided directly or fetched from Vault
SNO_BMC_USERNAME ?=
SNO_BMC_PASSWORD ?=
VAULT_BMC_SECRET_PATH ?=

# Vault AppRole Configuration - can be provided directly or fetched from Vault
VAULT_APPROLE_ROLE_ID ?=
VAULT_APPROLE_SECRET_ID ?=
VAULT_APPROLE_PATH ?=

# OpenStack Configuration
OPENSTACK_NAMESPACE ?=

# Internal Makefile paths (only these have defaults as they're not user config)
CI_FRAMEWORK_DIR ?= out/ci-framework
CI_FRAMEWORK_REPO ?= https://github.com/openstack-k8s-operators/ci-framework.git
CI_FRAMEWORK_BRANCH ?= main
OUTPUT_DIR ?= out/sno
PLAYBOOK_DIR ?= $(OUTPUT_DIR)/playbooks

# ============================================================================
# VALIDATION
# ============================================================================

define check_required_var
	@if [ -z "$($(1))" ]; then \
		echo "Error: $(1) is required but not set"; \
		exit 1; \
	fi
endef

.PHONY: validate_config
validate_config: ensure_bmc_credentials_file ## Validate that all required configuration variables are set
	$(call check_required_var,SNO_BMC_HOST)
	$(call check_required_var,SNO_NODE_MAC)
	@if [ ! -f "$(PULL_SECRET)" ]; then \
		echo "Error: Pull secret not found at $(PULL_SECRET)"; \
		exit 1; \
	fi
	@if [ ! -f "$(BMC_CREDENTIALS_FILE)" ]; then \
		echo "Error: BMC credentials file not found at $(BMC_CREDENTIALS_FILE)"; \
		echo "This should have been generated automatically - something went wrong"; \
		exit 1; \
	fi
	@echo "✔ All required configuration variables are set"

# validate_secrets removed - now handled by validate_config

.PHONY: ensure_bmc_credentials_file
ensure_bmc_credentials_file: ## Ensure BMC credentials file exists (create from env vars or Vault)
	@if [ ! -f "$(BMC_CREDENTIALS_FILE)" ]; then \
		echo "→ BMC credentials file not found, generating..."; \
		$(MAKE) generate_bmc_credentials_file; \
	fi

.PHONY: generate_bmc_credentials_file
generate_bmc_credentials_file: ## Generate BMC credentials YAML from environment or Vault
	@mkdir -p $$(dirname $(BMC_CREDENTIALS_FILE))
	@if [ -n "$(SNO_BMC_USERNAME)" ] && [ -n "$(SNO_BMC_PASSWORD)" ]; then \
		echo "→ Generating BMC credentials file from environment variables..."; \
		echo "---" > $(BMC_CREDENTIALS_FILE); \
		echo "username: $(SNO_BMC_USERNAME)" >> $(BMC_CREDENTIALS_FILE); \
		echo "password: $(SNO_BMC_PASSWORD)" >> $(BMC_CREDENTIALS_FILE); \
		chmod 600 $(BMC_CREDENTIALS_FILE); \
		echo "✔ BMC credentials saved to $(BMC_CREDENTIALS_FILE)"; \
	elif command -v vault >/dev/null 2>&1; then \
		echo "→ BMC credentials not in environment, fetching from Vault..."; \
		vault kv get -format=json $(VAULT_BMC_SECRET_PATH) | \
			jq -r '.data.data | "---\nusername: \(.username)\npassword: \(.password)"' \
			> $(BMC_CREDENTIALS_FILE) || (echo "✗ Failed to fetch from Vault" && exit 1); \
		chmod 600 $(BMC_CREDENTIALS_FILE); \
		echo "✔ BMC credentials fetched from Vault and saved to $(BMC_CREDENTIALS_FILE)"; \
	else \
		echo "✗ Error: BMC credentials not provided and Vault not available"; \
		echo "  Set SNO_BMC_USERNAME and SNO_BMC_PASSWORD, or install Vault CLI"; \
		exit 1; \
	fi

# ============================================================================
# PREPARATION
# ============================================================================

.PHONY: download_tools
download_tools: ## Install required tools and dependencies
	@echo "Installing required packages..."
	@sudo dnf -y install git ansible-core python3-pip podman nmstate tar
	@echo "Installing required Ansible collections..."
	@ansible-galaxy collection install community.crypto
	@echo "Installing OpenShift CLI (oc)..."
	@if ! command -v oc >/dev/null 2>&1; then \
		curl -sL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz | \
		sudo tar -xz -C /usr/local/bin oc kubectl; \
	fi
	@echo "✔ Required tools installed"

.PHONY: clone_ci_framework
clone_ci_framework: ## Clone or update ci-framework repository
	@echo "Setting up ci-framework..."
ifeq (,$(wildcard $(CI_FRAMEWORK_DIR)))
	@git clone $(CI_FRAMEWORK_REPO) $(CI_FRAMEWORK_DIR)
	@cd $(CI_FRAMEWORK_DIR) && git checkout $(CI_FRAMEWORK_BRANCH)
else
	@cd $(CI_FRAMEWORK_DIR) && git fetch origin && git checkout $(CI_FRAMEWORK_BRANCH) && git pull
endif
	@echo "✔ CI Framework ready at $(CI_FRAMEWORK_DIR)"

.PHONY: prepare_ansible_config
prepare_ansible_config: validate_config ## Generate Ansible variables and playbook
	@echo "Preparing Ansible configuration..."
	@mkdir -p $(PLAYBOOK_DIR)
	@$(MAKE) generate_vars_file
	@$(MAKE) generate_playbook
	@echo "✔ Ansible configuration prepared in $(PLAYBOOK_DIR)"

.PHONY: generate_vars_file
generate_vars_file:
	@echo "Generating vars.yaml..."
	@echo "---" > $(PLAYBOOK_DIR)/vars.yaml
	@echo "# SNO Configuration Variables" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_bm_sno: true" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_reproducer_basedir: $$(realpath $(OUTPUT_DIR))" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "# Cluster configuration" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_bm_agent_cluster_name: $(SNO_CLUSTER_NAME)" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_bm_agent_base_domain: $(SNO_BASE_DOMAIN)" >> $(PLAYBOOK_DIR)/vars.yaml
	@if [ -n "$(SNO_RELEASE_IMAGE)" ]; then \
		echo "cifmw_bm_agent_release_image: $(SNO_RELEASE_IMAGE)" >> $(PLAYBOOK_DIR)/vars.yaml; \
	else \
		echo 'cifmw_bm_agent_openshift_version: "$(SNO_OPENSHIFT_VERSION)"' >> $(PLAYBOOK_DIR)/vars.yaml; \
	fi
	@echo "" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "# Network configuration" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo 'cifmw_bm_agent_machine_network: "$(SNO_MACHINE_NETWORK)"' >> $(PLAYBOOK_DIR)/vars.yaml
	@echo 'cifmw_bm_agent_node_ip: "$(SNO_NODE_IP)"' >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_bm_agent_node_iface: $(SNO_NODE_IFACE)" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "# BMC configuration" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_bm_agent_bmc_host: $(SNO_BMC_HOST)" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "# Node configuration" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_bm_nodes:" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo '  - mac: "$(SNO_NODE_MAC)"' >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "    root_device: $(SNO_ROOT_DEVICE)" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "# Secrets" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_manage_secrets_pullsecret_file: $$(realpath $(PULL_SECRET))" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "cifmw_bmc_credentials_file: $$(realpath $(BMC_CREDENTIALS_FILE))" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "" >> $(PLAYBOOK_DIR)/vars.yaml
	@echo "# Optional configurations" >> $(PLAYBOOK_DIR)/vars.yaml
	@if [ -n "$(SNO_ISO_HTTP_PORT)" ]; then \
		echo "cifmw_bm_agent_iso_http_port: $(SNO_ISO_HTTP_PORT)" >> $(PLAYBOOK_DIR)/vars.yaml; \
	fi
	@if [ -n "$(SNO_INSTALLER_TIMEOUT)" ]; then \
		echo "cifmw_bm_agent_installer_timeout: $(SNO_INSTALLER_TIMEOUT)" >> $(PLAYBOOK_DIR)/vars.yaml; \
	fi
	@if [ -n "$(SNO_ENABLE_USB_BOOT)" ]; then \
		echo "cifmw_bm_agent_enable_usb_boot: $(SNO_ENABLE_USB_BOOT)" >> $(PLAYBOOK_DIR)/vars.yaml; \
	fi
	@if [ -n "$(SNO_LIVE_DEBUG)" ]; then \
		echo "cifmw_bm_agent_live_debug: $(SNO_LIVE_DEBUG)" >> $(PLAYBOOK_DIR)/vars.yaml; \
	fi
	@if [ -n "$(SNO_VMEDIA_UEFI_PATH)" ]; then \
		echo "cifmw_bm_agent_vmedia_uefi_path: $(SNO_VMEDIA_UEFI_PATH)" >> $(PLAYBOOK_DIR)/vars.yaml; \
	fi
	@if [ -n "$(SNO_CORE_PASSWORD)" ]; then \
		echo "cifmw_bm_agent_core_password: $(SNO_CORE_PASSWORD)" >> $(PLAYBOOK_DIR)/vars.yaml; \
	fi
	@if [ -n "$(SNO_DISABLED_IFACES)" ]; then \
		echo "cifmw_bm_agent_disabled_ifaces: $(SNO_DISABLED_IFACES)" >> $(PLAYBOOK_DIR)/vars.yaml; \
	fi
	@echo "✔ Generated $(PLAYBOOK_DIR)/vars.yaml"

.PHONY: generate_playbook
generate_playbook:
	@echo "Generating playbook.yaml..."
	@echo "---" > $(PLAYBOOK_DIR)/playbook.yaml
	@echo "- name: Deploy Single Node OpenShift" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "  hosts: localhost" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "  connection: local" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "  gather_facts: true" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "  vars_files:" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "    - vars.yaml" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "  tasks:" >> $(PLAYBOOK_DIR)/playbook.yaml
	@if [ -n "$(SNO_CONTROLLER_IP)" ]; then \
		echo "    - name: Override controller IP" >> $(PLAYBOOK_DIR)/playbook.yaml; \
		echo "      ansible.builtin.set_fact:" >> $(PLAYBOOK_DIR)/playbook.yaml; \
		echo "        ansible_default_ipv4:" >> $(PLAYBOOK_DIR)/playbook.yaml; \
		echo "          address: $(SNO_CONTROLLER_IP)" >> $(PLAYBOOK_DIR)/playbook.yaml; \
	fi
	@echo "    - name: Include bm_sno role" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "      ansible.builtin.include_role:" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "        name: bm_sno" >> $(PLAYBOOK_DIR)/playbook.yaml
	@echo "✔ Generated $(PLAYBOOK_DIR)/playbook.yaml"

.PHONY: generate_ansible_cfg
generate_ansible_cfg: ## Generate ansible.cfg for the deployment
	@echo "Generating ansible.cfg..."
	@echo "[defaults]" > $(PLAYBOOK_DIR)/ansible.cfg
	@echo "roles_path = $$(realpath $(CI_FRAMEWORK_DIR))/roles" >> $(PLAYBOOK_DIR)/ansible.cfg
	@echo "host_key_checking = False" >> $(PLAYBOOK_DIR)/ansible.cfg
	@echo "timeout = 30" >> $(PLAYBOOK_DIR)/ansible.cfg
	@echo "" >> $(PLAYBOOK_DIR)/ansible.cfg
	@echo "[privilege_escalation]" >> $(PLAYBOOK_DIR)/ansible.cfg
	@echo "become = False" >> $(PLAYBOOK_DIR)/ansible.cfg
	@echo "✔ Generated $(PLAYBOOK_DIR)/ansible.cfg"

# ============================================================================
# DEPLOYMENT
# ============================================================================

.PHONY: deploy_sno
deploy_sno: download_tools clone_ci_framework validate_config prepare_ansible_config generate_ansible_cfg ## Deploy Single Node OpenShift
	@echo "Starting SNO deployment..."
	@echo "Cluster: $(SNO_CLUSTER_NAME).$(SNO_BASE_DOMAIN)"
	@echo "BMC Host: $(SNO_BMC_HOST)"
	@echo "Node IP: $(SNO_NODE_IP)"
	@cd $(PLAYBOOK_DIR) && ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbook.yaml
	@echo "✔ SNO deployment completed"
	@$(MAKE) show_kubeconfig

.PHONY: show_kubeconfig
show_kubeconfig: ## Display kubeconfig location and access instructions
	@echo ""
	@echo "=========================================="
	@echo "SNO Deployment Complete!"
	@echo "=========================================="
	@echo ""
	@echo "To access your cluster, set:"
	@echo "  export KUBECONFIG=$(shell pwd)/$(OUTPUT_DIR)/artifacts/agent-install/auth/kubeconfig"
	@echo ""
	@echo "Or use:"
	@echo "  oc --kubeconfig=$(shell pwd)/$(OUTPUT_DIR)/artifacts/agent-install/auth/kubeconfig get nodes"
	@echo ""

# ============================================================================
# LVM STORAGE OPERATOR
# ============================================================================

.PHONY: install_lvm_operator
install_lvm_operator: ## Install LVM Storage Operator and configure LVM device
	@bash scripts/install_lvm_operator.sh

# ============================================================================
# GITOPS OPERATOR
# ============================================================================

.PHONY: clone_gitops
clone_gitops: ## Clone GitOps operator repository
	@if [ ! -d "$(GITOPS_DIR)" ]; then \
		echo "Cloning GitOps repository..."; \
		git clone $(GITOPS_REPO) $(GITOPS_DIR); \
	else \
		echo "GitOps repository already cloned at $(GITOPS_DIR)"; \
	fi

.PHONY: install_gitops_operator
install_gitops_operator: clone_gitops ## Install OpenShift GitOps Operator
	@echo "Installing OpenShift GitOps Operator..."
	@oc apply -k $(GITOPS_DIR)/openshift-gitops.deploy/subscribe/
	@echo "Waiting for GitOps Operator to be ready..."
	@until oc get deployment openshift-gitops-operator-controller-manager -n openshift-gitops-operator &>/dev/null; do \
		echo "  Waiting for operator deployment..."; \
		sleep 10; \
	done
	@oc wait --for=condition=Available=True -n openshift-gitops-operator deployment/openshift-gitops-operator-controller-manager --timeout=300s
	@echo "✔ OpenShift GitOps Operator installed"

.PHONY: enable_argocd
enable_argocd: ## Enable ArgoCD instance with OpenStack health checks
	@echo "Enabling ArgoCD with OpenStack integrations..."
	@oc apply -k $(GITOPS_DIR)/openshift-gitops.deploy/enable/
	@echo "Waiting for ArgoCD to be ready..."
	@until oc get deployment openshift-gitops-server -n openshift-gitops &>/dev/null; do \
		echo "  Waiting for ArgoCD deployment..."; \
		sleep 10; \
	done
	@oc wait --for=condition=Available=True -n openshift-gitops deployment/openshift-gitops-server --timeout=300s
	@echo "✔ ArgoCD enabled"
	@echo ""
	@echo "ArgoCD URL: https://$$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')"

.PHONY: deploy_openstack_dependencies
deploy_openstack_dependencies: clone_gitops ## Deploy OpenStack dependencies via ArgoCD (Cert-manager, MetalLB, NMState)
	@bash scripts/deploy_openstack_dependencies.sh

.PHONY: deploy_openstack_operator
deploy_openstack_operator: clone_gitops ## Deploy OpenStack operator via ArgoCD
	@bash scripts/deploy_openstack_operator.sh

.PHONY: deploy_vault_secrets_operator
deploy_vault_secrets_operator: clone_gitops ## Deploy Vault Secrets Operator via ArgoCD
	@bash scripts/deploy_vault_secrets_operator.sh

# ============================================================================
# OPENSTACK VAULT INTEGRATION
# ============================================================================

.PHONY: clone_gitops_tools
clone_gitops_tools: ## Clone GitOps tools repository
	@if [ ! -d "$(GITOPS_TOOLS_DIR)" ]; then \
		echo "Cloning GitOps tools repository..."; \
		git clone $(GITOPS_TOOLS_REPO) $(GITOPS_TOOLS_DIR); \
	else \
		echo "GitOps tools repository already cloned at $(GITOPS_TOOLS_DIR)"; \
	fi

.PHONY: configure_vault_authentication
configure_vault_authentication: clone_gitops_tools ## Configure Vault AppRole authentication for OpenStack namespace
	@if [ -z "$(OPENSTACK_NAMESPACE)" ]; then \
		echo "✗ Error: OPENSTACK_NAMESPACE not set"; \
		echo "  Set it in your config file or via: make configure_vault_authentication OPENSTACK_NAMESPACE=rhoso1"; \
		exit 1; \
	fi
	@if [ -n "$(VAULT_APPROLE_ROLE_ID)" ] && [ -n "$(VAULT_APPROLE_SECRET_ID)" ]; then \
		echo "→ Using AppRole credentials from environment variables..."; \
		ROLE_ID="$(VAULT_APPROLE_ROLE_ID)"; \
		SECRET_ID="$(VAULT_APPROLE_SECRET_ID)"; \
	elif [ -n "$(VAULT_APPROLE_PATH)" ] && command -v vault >/dev/null 2>&1; then \
		echo "→ Fetching AppRole credentials from Vault path: $(VAULT_APPROLE_PATH)..."; \
		ROLE_ID=$$(vault kv get -field=role_id $(VAULT_APPROLE_PATH)) || (echo "✗ Failed to fetch role_id from Vault" && exit 1); \
		SECRET_ID=$$(vault kv get -field=secret_id $(VAULT_APPROLE_PATH)) || (echo "✗ Failed to fetch secret_id from Vault" && exit 1); \
	else \
		echo "✗ Error: AppRole credentials not provided"; \
		echo "  Option 1: Set VAULT_APPROLE_ROLE_ID and VAULT_APPROLE_SECRET_ID"; \
		echo "  Option 2: Set VAULT_APPROLE_PATH and ensure vault CLI is available"; \
		exit 1; \
	fi; \
	echo "→ Configuring Vault AppRole authentication for namespace: $(OPENSTACK_NAMESPACE)..."; \
	$(MAKE) -C $(GITOPS_TOOLS_DIR) setup_vault \
		NAMESPACE=$(OPENSTACK_NAMESPACE) \
		APPROLE_ROLE_ID=$$ROLE_ID \
		APPROLE_SECRET_ID=$$SECRET_ID
	@echo "✔ Vault AppRole authentication configured for namespace: $(OPENSTACK_NAMESPACE)"

# ============================================================================
# UTILITY
# ============================================================================

.PHONY: show_config
show_config: ## Display current configuration
	@echo "=========================================="
	@echo "SNO Configuration"
	@echo "=========================================="
	@echo "Cluster Name:        $(SNO_CLUSTER_NAME)"
	@echo "Base Domain:         $(SNO_BASE_DOMAIN)"
	@echo "OpenShift Version:   $(SNO_OPENSHIFT_VERSION)"
	@echo ""
	@echo "Network Configuration:"
	@echo "  Machine Network:   $(SNO_MACHINE_NETWORK)"
	@echo "  Node IP:           $(SNO_NODE_IP)"
	@echo "  Node Interface:    $(SNO_NODE_IFACE)"
	@echo ""
	@echo "BMC Configuration:"
	@echo "  BMC Host:          $(SNO_BMC_HOST)"
	@echo "  Credentials File:  $(BMC_CREDENTIALS_FILE)"
	@echo ""
	@echo "Node Configuration:"
	@echo "  MAC Address:       $(SNO_NODE_MAC)"
	@echo "  Root Device:       $(SNO_ROOT_DEVICE)"
	@echo ""
	@echo "Paths:"
	@echo "  Pull Secret:       $(PULL_SECRET)"
	@echo "  Output Directory:  $(OUTPUT_DIR)"
	@echo "=========================================="

# setup_config, create_config_template, and create_bmc_credentials_template removed
# New simplified workflow:
#   1. cp configs/sno.example.sh configs/sno.local.sh
#   2. vi configs/sno.local.sh
#   3. source configs/sno.local.sh && make deploy_sno
# BMC credentials auto-fetched from Vault or set via SNO_BMC_USERNAME/PASSWORD

.PHONY: help
help: ## Display this help
	@echo ""
	@echo "SNO (Single Node OpenShift) Deployment Makefile"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make download_tools clone_ci_framework"
	@echo "  2. Set environment variables (see Configuration section below)"
	@echo "  3. make deploy_sno"
	@echo ""
	@echo "Note: BMC credentials auto-fetched from Vault ($(VAULT_BMC_SECRET_PATH))"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""
	@echo "Configuration (choose one method):"
	@echo ""
	@echo "  Method 1 - Direct environment variables (simplest):"
	@echo "    export SNO_BMC_HOST=idrac.example.com"
	@echo "    export SNO_NODE_MAC=b0:7b:25:xx:yy:zz"
	@echo "    export SNO_NODE_IP=192.168.10.50"
	@echo "    export SNO_NODE_IFACE=eno12399np0"
	@echo "    make deploy_sno"
	@echo ""
	@echo "  Method 2 - Config file (for repeated deployments):"
	@echo "    cp configs/sno.example.sh configs/sno.local.sh"
	@echo "    vi configs/sno.local.sh"
	@echo "    source configs/sno.local.sh && make deploy_sno"
	@echo ""
	@echo "  Method 3 - Command-line (for CI/CD):"
	@echo "    make deploy_sno SNO_BMC_HOST=... SNO_NODE_MAC=... SNO_NODE_IP=..."
	@echo ""
	@echo "  Required variables:"
	@echo "    SNO_BMC_HOST, SNO_NODE_MAC, SNO_NODE_IP, SNO_NODE_IFACE"
	@echo ""
	@echo "  See configs/sno.example.sh for all available options and defaults"
	@echo ""
	@echo "Example:"
	@echo '  make deploy_sno \\'
	@echo '    SNO_BMC_HOST=idrac.example.com \\'
	@echo '    SNO_NODE_MAC=b0:7b:25:xx:yy:zz \\'
	@echo '    SNO_NODE_IP=192.168.10.50 \\'
	@echo '    SNO_NODE_IFACE=eno12399np0'
	@echo ""

.DEFAULT_GOAL := help
