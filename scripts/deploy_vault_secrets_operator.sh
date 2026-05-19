#!/bin/bash

set -e

echo "Creating ArgoCD Application for Vault Secrets Operator..."

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vault-secrets-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/openstack-k8s-operators/gitops.git
    targetRevision: HEAD
    path: resources/vault-secrets-operator
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
echo "This will install the Vault Secrets Operator"
echo ""
echo "Monitor sync status:"
echo "  oc get application vault-secrets-operator -n openshift-gitops"
echo "  oc get subscription vault-secrets-operator -n openshift-operators"
