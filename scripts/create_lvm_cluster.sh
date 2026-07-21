#!/bin/bash

set -e

# Required environment variables:
# - SNO_LVM_DEVICES: Space-separated list of devices (e.g., "/dev/sdb /dev/sdc")
# - SNO_LVM_DEVICE_CLASS: Device class name (default: openstack)

SNO_LVM_DEVICE_CLASS="${SNO_LVM_DEVICE_CLASS:-openstack}"

# Build deviceSelector paths YAML
DEVICE_PATHS=""
for dev in ${SNO_LVM_DEVICES}; do
    DEVICE_PATHS="${DEVICE_PATHS}        - ${dev}
"
done
DEVICE_PATHS="${DEVICE_PATHS%
}"

echo "Creating LVMCluster..."
echo "Devices: ${SNO_LVM_DEVICES}"
echo "StorageClass: lvms-${SNO_LVM_DEVICE_CLASS}"

cat << EOF | oc apply -f -
apiVersion: lvm.topolvm.io/v1alpha1
kind: LVMCluster
metadata:
  name: lvmcluster-${SNO_LVM_DEVICE_CLASS}
  namespace: openshift-storage
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

echo "Waiting for LVMCluster to be ready..."
until oc get lvmcluster lvmcluster-${SNO_LVM_DEVICE_CLASS} -n openshift-storage -o jsonpath='{.status.ready}' 2>/dev/null | grep -q true; do
    echo "Waiting for LVMCluster to become ready..."
    sleep 10
done

echo "✔ LVMCluster created and ready"
echo ""
echo "StorageClass created: lvms-${SNO_LVM_DEVICE_CLASS}"
oc get storageclass lvms-${SNO_LVM_DEVICE_CLASS}
