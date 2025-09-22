#!/bin/bash

echo "🔧 Testing SharedResourceWarning fix for OpenShift AI"
echo "===================================================="

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo "❌ Error: Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

echo ""
echo "1️⃣ Current status of OpenShift AI application:"
oc get application openshift-ai-operator -n openshift-gitops -o jsonpath='{.status.sync.status}' || echo "Not found"
echo ""

echo ""
echo "2️⃣ Refreshing application to pick up Git changes..."
oc annotate application openshift-ai-operator -n openshift-gitops \
    argocd.argoproj.io/refresh=normal --overwrite

sleep 3

echo ""
echo "3️⃣ Syncing OpenShift AI application..."
oc patch application openshift-ai-operator -n openshift-gitops --type=merge \
    -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","prune":true}}}'

echo ""
echo "⏳ Waiting for sync to start..."
sleep 5

echo ""
echo "4️⃣ Checking sync status..."
for i in {1..6}; do
    STATUS=$(oc get application openshift-ai-operator -n openshift-gitops -o jsonpath='{.status.sync.status}')
    HEALTH=$(oc get application openshift-ai-operator -n openshift-gitops -o jsonpath='{.status.health.status}')
    echo "   Attempt $i: Sync=$STATUS, Health=$HEALTH"
    
    if [[ "$STATUS" == "Synced" ]]; then
        echo "   ✅ Sync completed!"
        break
    fi
    sleep 10
done

echo ""
echo "5️⃣ Checking for SharedResourceWarning..."
WARNINGS=$(oc get application openshift-ai-operator -n openshift-gitops -o json | jq -r '.status.conditions[]? | select(.type == "SharedResourceWarning") | .message' 2>/dev/null)

if [[ -n "$WARNINGS" ]]; then
    echo "   ⚠️  SharedResourceWarning still present:"
    echo "   $WARNINGS"
else
    echo "   ✅ No SharedResourceWarning found!"
fi

echo ""
echo "6️⃣ Checking GPU resources ownership..."
echo "   GPU Operator Application:"
oc get application nvidia-gpu-operator -n openshift-gitops -o jsonpath='{.status.resources}' 2>/dev/null | jq -r '.[] | select(.name == "gpu-cluster-policy") | "   - " + .kind + "/" + .name + " (managed by nvidia-gpu-operator)"' || echo "   - Not found in nvidia-gpu-operator app"

echo ""
echo "   OpenShift AI Application resources:"
oc get application openshift-ai-operator -n openshift-gitops -o jsonpath='{.status.resources}' 2>/dev/null | jq -r '.[] | select(.kind == "ClusterPolicy") | "   - " + .kind + "/" + .name + " (ERROR: should not be here!)"' || echo "   - No ClusterPolicy resources (good!)"

echo ""
echo "===================================================="
echo "Summary:"
echo "- Application sync status: $(oc get application openshift-ai-operator -n openshift-gitops -o jsonpath='{.status.sync.status}')"
echo "- Application health: $(oc get application openshift-ai-operator -n openshift-gitops -o jsonpath='{.status.health.status}')"

# Check if accelerator profile exists
echo ""
echo "7️⃣ Verifying GPU accelerator profile..."
if oc get acceleratorprofile nvidia-gpu -n redhat-ods-applications &>/dev/null; then
    echo "   ✅ GPU accelerator profile exists"
else
    echo "   ⚠️  GPU accelerator profile not found (may need GPU operator to be ready first)"
fi

echo ""
echo "Done! Monitor the application with:"
echo "  oc get application openshift-ai-operator -n openshift-gitops -w"
