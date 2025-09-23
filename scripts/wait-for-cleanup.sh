#!/bin/bash

echo "⏳ Waiting for cluster cleanup to complete..."
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check namespaces that should be gone
NAMESPACES_TO_CHECK=(
    "openshift-gitops"
    "openshift-gitops-operator" 
    "redhat-ods-operator"
    "redhat-ods-applications"
    "redhat-ods-monitoring"
    "istio-system"
    "knative-serving"
    "knative-eventing"
    "nvidia-gpu-operator"
    "openshift-nfd"
    "anythingllm"
    "minio"
)

echo "Checking namespace termination status..."
echo ""

WAITING=true
while $WAITING; do
    WAITING=false
    
    for ns in "${NAMESPACES_TO_CHECK[@]}"; do
        if oc get namespace $ns &>/dev/null 2>&1; then
            STATUS=$(oc get namespace $ns -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            if [[ "$STATUS" == "Terminating" ]]; then
                echo -e "${YELLOW}⏳ $ns is still terminating...${NC}"
                WAITING=true
            else
                echo -e "${RED}❌ $ns still exists (status: $STATUS)${NC}"
                WAITING=true
            fi
        fi
    done
    
    if $WAITING; then
        echo ""
        echo "Waiting 10 seconds before checking again..."
        sleep 10
        echo ""
    fi
done

echo -e "${GREEN}✅ All namespaces have been removed!${NC}"
echo ""

# Check for any finalizers blocking deletion
echo "Checking for stuck resources..."
STUCK_NS=$(oc get namespace -o json | jq -r '.items[] | select(.status.phase=="Terminating") | .metadata.name' 2>/dev/null)

if [[ -n "$STUCK_NS" ]]; then
    echo -e "${YELLOW}⚠️  Found stuck namespaces:${NC}"
    echo "$STUCK_NS"
    echo ""
    echo "You may need to manually remove finalizers. Run:"
    echo "  oc get namespace <namespace> -o yaml"
    echo "  # Look for finalizers section and remove them"
    echo ""
else
    echo -e "${GREEN}✅ No stuck namespaces found${NC}"
fi

# Final checks
echo ""
echo "Final verification..."
echo ""

echo "Operators remaining:"
oc get csv -A 2>/dev/null | grep -v "NAME" | grep -v "packageserver" || echo "  None found"

echo ""
echo "Custom Resource Definitions remaining:"
CRD_COUNT=$(oc get crd -o name | grep -E "(servicemesh|maistra|kiali|jaeger|elastic|knative|serving|eventing|datasciencecluster|notebook|nfd|nvidia)" | wc -l || echo "0")
if [[ "$CRD_COUNT" -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Found $CRD_COUNT CRDs that may need manual removal${NC}"
else
    echo -e "${GREEN}✅ No problematic CRDs found${NC}"
fi

echo ""
echo "=========================================="
echo ""

if [[ "$CRD_COUNT" -eq 0 ]]; then
    echo -e "${GREEN}✅ Cluster is ready for bootstrap!${NC}"
    echo ""
    echo "You can now run:"
    echo "  ./bootstrap.sh"
else
    echo -e "${YELLOW}⚠️  Some cleanup may still be needed${NC}"
    echo ""
    echo "Check remaining CRDs with:"
    echo "  oc get crd | grep -E '(servicemesh|maistra|kiali|jaeger|elastic|knative|serving|eventing|datasciencecluster|notebook|nfd|nvidia)'"
fi
