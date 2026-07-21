#!/bin/bash

set -e

# Required environment variables:
# - SNO_OPENSHIFT_VERSION: OpenShift version (e.g., 4.18.41)

CHANNEL=$(echo "${SNO_OPENSHIFT_VERSION}" | cut -d. -f1-2)

echo "Installing LVM Storage Operator..."
echo "Channel: stable-${CHANNEL}"

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

echo "✔ LVM Storage Operator installed"
