#!/bin/bash

set -e

echo "Creating ArgoCD Application for OpenStack Operator CR..."
echo ""
echo "This will deploy the OpenStack CR which bootstraps all service operators"
echo "and creates CRDs for: NetConfig, OpenStackControlPlane, OpenStackDataPlaneNodeSet, etc."
echo ""

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openstack-operator-cr
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/openstack-k8s-operators/gitops.git
    targetRevision: HEAD
    path: example/openstack-operator-cr
  destination:
    server: https://kubernetes.default.svc
    namespace: openstack-operators
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=false
EOF

echo "✔ ArgoCD Application created"
echo ""
echo "This will deploy the OpenStack CR to bootstrap all service operators"
echo ""
echo "Monitor deployment:"
echo "  oc get application openstack-operator-cr -n openshift-gitops"
echo "  oc get openstacks.operator.openstack.org -n openstack-operators"
echo "  oc get pods -n openstack-operators"
echo ""
echo "Wait for all service operator CRDs to be created (this may take 5-10 minutes):"
echo "  watch 'oc get crd | grep openstack'"
echo ""
