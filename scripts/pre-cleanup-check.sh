#!/bin/bash

echo "🔍 Pre-Cleanup Check Script"
echo "==========================="
echo ""
echo "This script shows what would be removed by cleanup-cluster.sh"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo "❌ Not logged into OpenShift"
    exit 1
fi

echo -e "${GREEN}✅ Logged in as: $(oc whoami)${NC}"
echo ""

echo "Resources that would be removed:"
echo ""

echo "📦 GitOps Applications:"
APP_COUNT=$(oc get applications -n openshift-gitops --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$APP_COUNT" -gt 0 ]]; then
    oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status
else
    echo "  None found"
fi

echo ""
echo "📦 Operators:"
echo "  OpenShift AI: $(oc get csv -n redhat-ods-operator 2>/dev/null | grep rhods-operator | wc -l || echo "0") instances"
echo "  Service Mesh: $(oc get csv -n openshift-operators 2>/dev/null | grep servicemeshoperator | wc -l || echo "0") instances"
echo "  Serverless: $(oc get csv -n openshift-serverless 2>/dev/null | grep serverless-operator | wc -l || echo "0") instances"
echo "  GPU Operator: $(oc get csv -n nvidia-gpu-operator 2>/dev/null | grep gpu-operator | wc -l || echo "0") instances"
echo "  NFD: $(oc get csv -n openshift-nfd 2>/dev/null | grep nfd | wc -l || echo "0") instances"
echo "  Pipelines: $(oc get csv -n openshift-operators 2>/dev/null | grep pipelines | wc -l || echo "0") instances"
echo "  GitOps: $(oc get csv -n openshift-gitops-operator 2>/dev/null | grep gitops | wc -l || echo "0") instances"

echo ""
echo "📦 Namespaces that would be removed:"
for ns in anythingllm redhat-ods-operator redhat-ods-applications redhat-ods-monitoring istio-system knative-serving knative-eventing nvidia-gpu-operator openshift-nfd minio; do
    if oc get namespace $ns &>/dev/null; then
        echo -e "  ${YELLOW}$ns${NC}"
    fi
done

echo ""
echo "📦 GPU Nodes:"
GPU_COUNT=$(oc get nodes -l node-role.kubernetes.io/gpu --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$GPU_COUNT" -gt 0 ]]; then
    echo "  Found $GPU_COUNT GPU nodes that would be removed:"
    oc get nodes -l node-role.kubernetes.io/gpu -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type
else
    echo "  None found"
fi

echo ""
echo "📦 Service Mesh Resources:"
SMCP_COUNT=$(oc get smcp -A --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$SMCP_COUNT" -gt 0 ]]; then
    oc get smcp -A
else
    echo "  None found"
fi

echo ""
echo "📦 Knative Resources:"
KS_COUNT=$(oc get knativeserving -A --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$KS_COUNT" -gt 0 ]]; then
    oc get knativeserving -A
else
    echo "  None found"
fi

echo ""
echo "📦 DataScienceCluster:"
DSC_COUNT=$(oc get datasciencecluster -A --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$DSC_COUNT" -gt 0 ]]; then
    oc get datasciencecluster -A
else
    echo "  None found"
fi

echo ""
echo "==========================="
echo ""
echo "To proceed with cleanup, run:"
echo "  ./scripts/cleanup-cluster.sh"
echo ""
echo "To test bootstrap on a fresh cluster, you could either:"
echo "1. Run cleanup-cluster.sh on this cluster"
echo "2. Provision a new OpenShift cluster"
