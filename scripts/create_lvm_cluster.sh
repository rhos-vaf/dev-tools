#!/bin/bash

set -e

# Required environment variables:
# - SNO_LVM_DEVICES: Space-separated list of devices (e.g., "/dev/sdb /dev/sdc")
# - SNO_LVM_DEVICE_CLASS: Device class name (default: openstack)

SNO_LVM_DEVICE_CLASS="${SNO_LVM_DEVICE_CLASS:-openstack}"
SNO_LVM_CLUSTER_NAME="${SNO_LVM_CLUSTER_NAME:-lvmcluster}"
SNO_LVM_NAMESPACE="${SNO_LVM_NAMESPACE:-openshift-storage}"

# Build deviceSelector optionalPaths YAML
DEVICE_PATHS=""
for dev in ${SNO_LVM_DEVICES}; do
    DEVICE_PATHS="${DEVICE_PATHS}        - ${dev}
"
done
DEVICE_PATHS="${DEVICE_PATHS%
}"

echo "Creating/updating LVMCluster deviceClass: ${SNO_LVM_DEVICE_CLASS}"
echo "Devices: ${SNO_LVM_DEVICES}"
echo "StorageClass: lvms-${SNO_LVM_DEVICE_CLASS}"

if oc get lvmcluster ${SNO_LVM_CLUSTER_NAME} -n ${SNO_LVM_NAMESPACE} &>/dev/null; then
    echo "LVMCluster already exists, adding deviceClass..."
    PATCH=$(cat <<EOFPATCH
[{
  "op": "add",
  "path": "/spec/storage/deviceClasses/-",
  "value": {
    "name": "${SNO_LVM_DEVICE_CLASS}",
    "thinPoolConfig": {
      "name": "thin-pool-${SNO_LVM_DEVICE_CLASS}",
      "sizePercent": 90,
      "overprovisionRatio": 10
    },
    "deviceSelector": {
      "optionalPaths": [$(echo ${SNO_LVM_DEVICES} | sed 's|[^ ]*|"&"|g' | sed 's| |, |g')]
    }
  }
}]
EOFPATCH
)
    oc patch lvmcluster ${SNO_LVM_CLUSTER_NAME} -n ${SNO_LVM_NAMESPACE} --type=json -p "${PATCH}"
else
    echo "Creating new LVMCluster..."
    cat << EOF | oc apply -f -
apiVersion: lvm.topolvm.io/v1alpha1
kind: LVMCluster
metadata:
  name: ${SNO_LVM_CLUSTER_NAME}
  namespace: ${SNO_LVM_NAMESPACE}
spec:
  storage:
    deviceClasses:
    - name: ${SNO_LVM_DEVICE_CLASS}
      thinPoolConfig:
        name: thin-pool-${SNO_LVM_DEVICE_CLASS}
        sizePercent: 90
        overprovisionRatio: 10
      deviceSelector:
        optionalPaths:
${DEVICE_PATHS}
EOF
fi

echo "Waiting for LVMCluster to be ready..."
until oc get lvmcluster ${SNO_LVM_CLUSTER_NAME} -n ${SNO_LVM_NAMESPACE} -o jsonpath='{.status.ready}' 2>/dev/null | grep -q true; do
    echo "Waiting for LVMCluster to become ready..."
    sleep 10
done

echo "✔ LVMCluster ready with deviceClass: ${SNO_LVM_DEVICE_CLASS}"
echo ""
echo "StorageClass created: lvms-${SNO_LVM_DEVICE_CLASS}"
oc get storageclass lvms-${SNO_LVM_DEVICE_CLASS}
