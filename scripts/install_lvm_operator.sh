#!/bin/bash

set -e

# Required environment variables:
# - SNO_LVM_DEVICE: Device to use for LVM (e.g., /dev/sdb)
# - SNO_LVM_DEVICE_CLASS: Device class name (default: openstack)
# - SNO_OPENSHIFT_VERSION: OpenShift version (e.g., 4.20.22)

if [ -z "${SNO_LVM_DEVICE}" ]; then
    echo "Error: SNO_LVM_DEVICE is not set"
    echo "Set it in your config file: export SNO_LVM_DEVICE=/dev/sdb"
    exit 1
fi

SNO_LVM_DEVICE_CLASS="${SNO_LVM_DEVICE_CLASS:-openstack}"
CHANNEL=$(echo "${SNO_OPENSHIFT_VERSION}" | cut -d. -f1-2)

echo "Installing LVM Storage Operator..."
echo "Device: ${SNO_LVM_DEVICE}"
echo "StorageClass: lvms-${SNO_LVM_DEVICE_CLASS}"

# Create namespace
oc create namespace openshift-storage || true

# Create OperatorGroup
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
EOF

# Create Subscription
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: lvms-operator
  namespace: openshift-storage
spec:
  channel: stable-${CHANNEL}
  installPlanApproval: Automatic
  name: lvms-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo "Waiting for LVM Operator deployment to be created..."
until oc get deployment lvms-operator -n openshift-storage &>/dev/null; do
    echo "  Waiting for operator deployment..."
    sleep 10
done

echo "Waiting for LVM Operator to be ready..."
oc wait --for=condition=Available=True -n openshift-storage deployment/lvms-operator --timeout=300s

# Create LVMCluster
echo "Creating LVMCluster..."
cat << EOF | oc apply -f -
apiVersion: lvm.topolvm.io/v1alpha1
kind: LVMCluster
metadata:
  name: lvmcluster
  namespace: openshift-storage
spec:
  storage:
    deviceClasses:
    - name: ${SNO_LVM_DEVICE_CLASS}
      thinPoolConfig:
        name: thin-pool-1
        sizePercent: 90
        overprovisionRatio: 10
      deviceSelector:
        paths:
        - ${SNO_LVM_DEVICE}
EOF

echo "Waiting for LVMCluster to be ready..."
until oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.ready}' 2>/dev/null | grep -q true; do
    echo "Waiting for LVMCluster to become ready..."
    sleep 10
done

echo "✔ LVM Storage Operator installed and configured"
echo ""
echo "StorageClass created: lvms-${SNO_LVM_DEVICE_CLASS}"
oc get storageclass lvms-${SNO_LVM_DEVICE_CLASS}
