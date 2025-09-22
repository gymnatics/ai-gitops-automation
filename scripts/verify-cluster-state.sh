#!/bin/bash

echo "🔍 Verifying OpenShift Cluster State"
echo "===================================="

# Check login status
echo ""
echo "1️⃣ Checking OpenShift login..."
if oc whoami &>/dev/null; then
    echo "✅ Logged in as: $(oc whoami)"
    echo "   Server: $(oc whoami --show-server)"
else
    echo "❌ Not logged in to OpenShift"
    exit 1
fi

# Check GitOps
echo ""
echo "2️⃣ Checking OpenShift GitOps..."
if oc get csv -n openshift-gitops-operator | grep -q "openshift-gitops-operator.*Succeeded"; then
    echo "✅ GitOps operator is installed"
    echo "   Applications:"
    oc get applications -n openshift-gitops 2>/dev/null | tail -n +2 | awk '{print "   - " $1 " (" $2 ")"}'
else
    echo "❌ GitOps operator not found"
fi

# Check OpenShift AI
echo ""
echo "3️⃣ Checking OpenShift AI..."
if oc get csv -n redhat-ods-operator | grep -q "rhods-operator.*Succeeded"; then
    echo "✅ OpenShift AI operator is installed"
    VERSION=$(oc get csv -n redhat-ods-operator | grep rhods-operator | awk '{print $1}')
    echo "   Version: ${VERSION}"
    
    # Check DataScienceCluster
    if oc get datasciencecluster -n redhat-ods-applications default &>/dev/null; then
        echo "✅ DataScienceCluster 'default' exists"
        echo "   Components:"
        oc get datasciencecluster default -n redhat-ods-applications -o json | jq -r '.spec.components | to_entries[] | select(.value.managementState == "Managed") | "   - " + .key'
    else
        echo "⚠️  No DataScienceCluster found"
    fi
else
    echo "❌ OpenShift AI operator not found"
fi

# Check GPU support
echo ""
echo "4️⃣ Checking GPU support..."
if oc get csv -n nvidia-gpu-operator | grep -q "gpu-operator.*Succeeded" 2>/dev/null; then
    echo "✅ GPU operator is installed"
    GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)
    echo "   GPU nodes: ${GPU_NODES}"
else
    echo "ℹ️  GPU operator not installed"
fi

# Check existing tenants
echo ""
echo "5️⃣ Checking existing tenants..."
TENANT_NAMESPACES=$(oc get namespaces -l opendatahub.io/dashboard=true --no-headers 2>/dev/null | grep -v redhat-ods | awk '{print $1}')
if [[ -n "${TENANT_NAMESPACES}" ]]; then
    echo "   Existing tenant namespaces:"
    for ns in ${TENANT_NAMESPACES}; do
        echo "   - ${ns}"
    done
else
    echo "   No tenant namespaces found"
fi

# Check for AnythingLLM
echo ""
echo "6️⃣ Checking for AnythingLLM..."
if oc get namespace anythingllm &>/dev/null 2>&1; then
    echo "⚠️  AnythingLLM namespace already exists!"
    echo "   Resources in namespace:"
    oc get all -n anythingllm 2>/dev/null | tail -n +2 | awk '{print "   - " $1}'
else
    echo "✅ AnythingLLM namespace does not exist (ready for deployment)"
fi

echo ""
echo "===================================="
echo "Verification complete!"
