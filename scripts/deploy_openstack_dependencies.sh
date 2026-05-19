#!/bin/bash

set -e

echo "Creating ArgoCD Application for OpenStack dependencies..."

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openstack-dependencies
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/openstack-k8s-operators/gitops.git
    targetRevision: HEAD
    path: example/dependencies
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
echo "Monitor sync status:"
echo "  oc get application openstack-dependencies -n openshift-gitops"
echo "  argocd app get openstack-dependencies"
