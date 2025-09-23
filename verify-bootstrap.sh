#!/bin/bash

echo "🔍 Bootstrap Verification Script"
echo "================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo -e "${RED}❌ Not logged into OpenShift${NC}"
    echo "Please run: oc login"
    exit 1
fi

echo -e "${GREEN}✅ Logged in as: $(oc whoami)${NC}"
echo ""

echo "1️⃣ Checking GitOps Installation..."
if oc get csv -n openshift-gitops-operator | grep -q "openshift-gitops-operator.*Succeeded"; then
    echo -e "${GREEN}✅ GitOps operator is installed${NC}"
else
    echo -e "${RED}❌ GitOps operator is NOT installed${NC}"
    exit 1
fi

echo ""
echo "2️⃣ Checking GitOps Applications..."
APP_COUNT=$(oc get applications -n openshift-gitops --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$APP_COUNT" -gt 0 ]]; then
    echo -e "${GREEN}✅ Found $APP_COUNT GitOps applications${NC}"
    echo ""
    echo "Application Status:"
    oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REPO:.spec.source.repoURL
else
    echo -e "${RED}❌ No GitOps applications found${NC}"
    echo ""
    echo "Checking ApplicationSets..."
    oc get applicationsets -n openshift-gitops
fi

echo ""
echo "3️⃣ Checking Critical Operators..."
for op in "openshift-ai" "servicemesh" "serverless" "gitops"; do
    if oc get applications -n openshift-gitops | grep -q "$op"; then
        echo -e "${GREEN}✅ $op application exists${NC}"
    else
        echo -e "${YELLOW}⚠️  $op application missing${NC}"
    fi
done

echo ""
echo "4️⃣ Checking Tenant Applications..."
if oc get applications -n openshift-gitops | grep -q "anythingllm"; then
    echo -e "${GREEN}✅ AnythingLLM application exists${NC}"
else
    echo -e "${YELLOW}⚠️  AnythingLLM application missing${NC}"
fi

echo ""
echo "5️⃣ Checking Sync Issues..."
SYNC_ISSUES=$(oc get applications -n openshift-gitops -o json | jq -r '.items[] | select(.status.sync.status != "Synced") | .metadata.name' | wc -l)
if [[ "$SYNC_ISSUES" -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Found $SYNC_ISSUES applications with sync issues:${NC}"
    oc get applications -n openshift-gitops -o json | jq -r '.items[] | select(.status.sync.status != "Synced") | "\(.metadata.name): \(.status.sync.status) - \(.status.conditions[0].message // "No message")"'
else
    echo -e "${GREEN}✅ All applications are synced${NC}"
fi

echo ""
echo "6️⃣ Checking OpenShift AI Components..."
if oc get datasciencecluster -n redhat-ods-operator &>/dev/null 2>&1; then
    echo -e "${GREEN}✅ DataScienceCluster exists${NC}"
    DSC_READY=$(oc get datasciencecluster -n redhat-ods-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
    echo "   Status: $DSC_READY"
else
    echo -e "${RED}❌ DataScienceCluster missing${NC}"
fi

echo ""
echo "7️⃣ Quick Fixes Available:"
echo ""
echo "If applications are missing, run:"
echo "  oc apply -k components/argocd/apps/base/"
echo ""
echo "If cluster-config app is missing, run:"
echo "  oc apply -f components/argocd/apps/base/cluster-config-app-of-apps.yaml"
echo ""
echo "To force sync all applications:"
echo "  for app in \$(oc get applications -n openshift-gitops -o name); do"
echo "    oc annotate \$app -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite"
echo "  done"
