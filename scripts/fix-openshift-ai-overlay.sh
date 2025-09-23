#!/bin/bash
set -e

echo "🔧 Fixing OpenShift AI Overlay Configuration"
echo "==========================================="

# Check if logged into OpenShift
if ! oc whoami &>/dev/null; then
    echo "❌ Error: Not logged into OpenShift. Please run 'oc login' first."
    exit 1
fi

# Find the OpenShift AI application
echo "Looking for OpenShift AI application..."
AI_APP=$(oc get applications -n openshift-gitops -o name 2>/dev/null | grep openshift-ai || echo "")

if [ -z "$AI_APP" ]; then
    echo "❌ OpenShift AI application not found!"
    exit 1
fi

echo "Found: $AI_APP"

# Get current path
CURRENT_PATH=$(oc get $AI_APP -n openshift-gitops -o jsonpath='{.spec.source.path}' 2>/dev/null || echo "unknown")
echo "Current path: $CURRENT_PATH"

# Determine correct path based on GPU configuration
if [[ "$CURRENT_PATH" == *"-nvidia-gpu" ]]; then
    CORRECT_PATH="components/operators/openshift-ai/aggregate/overlays/stable-nvidia-gpu"
else
    CORRECT_PATH="components/operators/openshift-ai/aggregate/overlays/stable"
fi

echo "Correct path should be: $CORRECT_PATH"

# Update the application if needed
if [[ "$CURRENT_PATH" != "$CORRECT_PATH" ]]; then
    echo "Updating OpenShift AI application path..."
    
    # Patch the application
    oc patch $AI_APP -n openshift-gitops --type=merge -p "{
        \"spec\": {
            \"source\": {
                \"path\": \"$CORRECT_PATH\"
            }
        }
    }"
    
    echo "✅ Application path updated"
    
    # Force sync
    echo "Force syncing the application..."
    oc patch $AI_APP -n openshift-gitops --type=merge -p '{
        "operation": {
            "sync": {
                "force": true,
                "prune": true
            }
        }
    }'
    
    echo "✅ Sync initiated"
else
    echo "✅ Application path is already correct"
fi

# Check ApplicationSet configuration
echo ""
echo "Checking ApplicationSet configuration..."
APPSET_PATH=$(oc get applicationset cluster-operators -n openshift-gitops -o yaml 2>/dev/null | grep -A2 "openshift-ai-operator" | grep "path:" | awk '{print $2}' || echo "")

if [ -n "$APPSET_PATH" ]; then
    echo "ApplicationSet path: $APPSET_PATH"
    
    if [[ "$APPSET_PATH" != "$CORRECT_PATH" ]]; then
        echo "⚠️  ApplicationSet has different path than expected"
        echo "This might be overridden by a patch. Checking patches..."
        
        # Look for patch files
        if [ -f "/Users/dayeo/ai-gitops-automation/clusters/overlays/dynamic/patch-operators-list.yaml" ]; then
            echo "Dynamic patch exists. Checking content..."
            grep -A3 "openshift-ai-operator" /Users/dayeo/ai-gitops-automation/clusters/overlays/dynamic/patch-operators-list.yaml
        fi
    fi
fi

echo ""
echo "🎯 Summary:"
echo "- Application updated to use: $CORRECT_PATH"
echo "- Sync initiated to apply changes"
echo ""
echo "Next steps:"
echo "1. Wait 1-2 minutes for sync to complete"
echo "2. Check ArgoCD UI for sync status"
echo "3. Verify OpenShift AI operator is healthy"

# Get ArgoCD route
ARGO_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$ARGO_ROUTE" ]; then
    echo ""
    echo "ArgoCD UI: https://$ARGO_ROUTE"
fi
