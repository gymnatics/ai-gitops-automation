#!/bin/bash
# Fix for immutable job field error

echo "🔧 Fixing GitOps console plugin job..."

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo "❌ Error: Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

# Delete the existing job if it exists
echo "🗑️  Deleting existing job..."
oc delete job job-gitops-console-plugin -n openshift-gitops --ignore-not-found=true

# Also delete any related pods
oc delete pods -n openshift-gitops -l job-name=job-gitops-console-plugin --ignore-not-found=true

# Wait for resources to be fully deleted
echo "⏳ Waiting for resources to be deleted..."
sleep 10

# Check if the job is truly gone
if oc get job job-gitops-console-plugin -n openshift-gitops &>/dev/null 2>&1; then
    echo "⚠️  Job still exists, forcing deletion..."
    oc delete job job-gitops-console-plugin -n openshift-gitops --force --grace-period=0
    sleep 5
fi

# Refresh the application to pick up latest changes
echo "🔄 Refreshing application..."
oc annotate application openshift-gitops-operator -n openshift-gitops \
    argocd.argoproj.io/refresh=normal --overwrite

# Wait a moment for refresh
sleep 3

# Force sync the application
echo "📡 Syncing openshift-gitops-operator application..."
oc patch application openshift-gitops-operator -n openshift-gitops --type=json \
    -p='[{"op": "replace", "path": "/spec/syncPolicy/retry/limit", "value": 10}]' || true

# Trigger sync using API
oc patch application openshift-gitops-operator -n openshift-gitops --type=merge \
    -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","prune":true,"syncOptions":["Replace=true"]}}}'

echo ""
echo "✅ Fix applied!"
echo ""
echo "Monitor the sync status with:"
echo "  oc get application openshift-gitops-operator -n openshift-gitops"
echo ""
echo "Check job status with:"
echo "  oc get jobs -n openshift-gitops"
