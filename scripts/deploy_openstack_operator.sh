#!/bin/bash

set -e

echo "Creating ArgoCD Application for OpenStack Operator..."

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openstack-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/openstack-k8s-operators/gitops.git
    targetRevision: HEAD
    path: example/openstack-operator
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

echo "✔ ArgoCD Application created"
echo ""
echo "This will install the OpenStack operator from Red Hat Operator Hub"
echo ""
echo "Monitor sync status:"
echo "  oc get application openstack-operator -n openshift-gitops"
echo "  oc get csv -n openstack-operators"
