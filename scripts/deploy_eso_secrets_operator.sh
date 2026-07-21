#!/bin/bash

set -e

echo "Creating ArgoCD Application for External Secrets Operator..."

cat << EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/openstack-k8s-operators/gitops.git
    targetRevision: HEAD
    path: resources/external-secrets-operator/redhat
    kustomize:
      components:
        - https://github.com/openstack-k8s-operators/gitops/components/argocd/annotations?ref=main
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

echo "✔ ArgoCD Application created"
echo ""
echo "This will install the Red Hat External Secrets Operator"
echo ""
echo "Monitor sync status:"
echo "  oc get application external-secrets-operator -n openshift-gitops"
echo "  oc get subscription openshift-external-secrets-operator -n external-secrets-operator"
