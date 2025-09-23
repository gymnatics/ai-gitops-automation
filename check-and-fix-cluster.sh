#!/bin/bash

echo "🔍 OpenShift Cluster Check and Fix Script"
echo "========================================"
echo ""
echo "This script assumes you are already logged into OpenShift"
echo ""

# First check if we're logged in
if ! oc whoami &>/dev/null; then
    echo "❌ Not logged into OpenShift. Please run:"
    echo "   oc login -u <username> -p <password> <server>"
    exit 1
fi

echo "✅ Logged in as: $(oc whoami)"
echo "   Server: $(oc whoami --show-server)"
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "1️⃣  CHECKING GITOPS APPLICATIONS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "All GitOps Applications:"
oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status --sort-by=.metadata.name

echo ""
echo "Applications with sync issues:"
oc get applications -n openshift-gitops -o json | jq -r '.items[] | select(.status.sync.status != "Synced") | "\(.metadata.name): Sync=\(.status.sync.status), Health=\(.status.health.status)"'

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "2️⃣  CHECKING SERVICE MESH"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if Service Mesh operator is installed
if oc get csv -n openshift-operators | grep -q servicemeshoperator; then
    echo "✅ Service Mesh Operator is installed"
    
    # Check for control plane
    if ! oc get smcp -n istio-system basic &>/dev/null 2>&1; then
        echo "❌ Service Mesh Control Plane missing - Creating it..."
        
        # Create namespace if needed
        oc create namespace istio-system --dry-run=client -o yaml | oc apply -f -
        
        # Create SMCP
        cat <<EOF | oc apply -f -
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
  namespace: istio-system
spec:
  version: v2.5
  tracing:
    type: Jaeger
    sampling: 10000
  policy:
    type: Istiod
  telemetry:
    type: Istiod
  addons:
    jaeger:
      install:
        storage:
          type: Memory
    prometheus:
      enabled: true
    kiali:
      enabled: true
    grafana:
      enabled: true
EOF
        
        # Create SMMR
        cat <<EOF | oc apply -f -
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
  namespace: istio-system
spec:
  members:
    - redhat-ods-operator
    - redhat-ods-applications
    - knative-serving
EOF
        echo "✅ Created Service Mesh Control Plane and Member Roll"
    else
        echo "✅ Service Mesh Control Plane exists"
        oc get smcp -n istio-system
    fi
else
    echo "❌ Service Mesh Operator NOT installed - GitOps should handle this"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "3️⃣  CHECKING SERVERLESS/KNATIVE"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if Serverless operator is installed
if oc get csv -n openshift-serverless | grep -q serverless-operator; then
    echo "✅ Serverless Operator is installed"
    
    # Check for Knative Serving
    if ! oc get knativeserving -n knative-serving knative-serving &>/dev/null 2>&1; then
        echo "❌ Knative Serving missing - Creating it..."
        
        # Create namespace if needed
        oc create namespace knative-serving --dry-run=client -o yaml | oc apply -f -
        
        # Create KnativeServing
        cat <<EOF | oc apply -f -
apiVersion: operator.knative.dev/v1beta1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: knative-serving
  annotations:
    serverless.openshift.io/default-enable-http2: "true"
spec:
  ingress:
    istio:
      enabled: true
  config:
    network:
      domainTemplate: "{{.Name}}-{{.Namespace}}.{{.Domain}}"
EOF
        echo "✅ Created Knative Serving"
    else
        echo "✅ Knative Serving exists"
        oc get knativeserving -n knative-serving
    fi
else
    echo "❌ Serverless Operator NOT installed - GitOps should handle this"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "4️⃣  CHECKING OPENSHIFT AI"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if RHOAI operator is installed
if oc get csv -n redhat-ods-operator | grep -q rhods-operator; then
    echo "✅ OpenShift AI Operator is installed"
    
    # Check for DataScienceCluster
    if ! oc get datasciencecluster -n redhat-ods-operator &>/dev/null 2>&1; then
        echo "❌ DataScienceCluster missing - Creating it..."
        
        cat <<EOF | oc apply -f -
apiVersion: datasciencecluster.opendatahub.io/v1
kind: DataScienceCluster
metadata:
  name: default-dsc
  namespace: redhat-ods-operator
spec:
  components:
    codeflare:
      managementState: Removed
    dashboard:
      managementState: Managed
    datasciencepipelines:
      managementState: Managed
    kserve:
      managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: SelfSigned
        managementState: Managed
        name: knative-serving
    kueue:
      managementState: Removed
    modelmeshserving:
      managementState: Managed
    ray:
      managementState: Removed
    trustyai:
      managementState: Removed
    workbenches:
      managementState: Managed
EOF
        echo "✅ Created DataScienceCluster"
    else
        echo "✅ DataScienceCluster exists"
        oc get datasciencecluster -n redhat-ods-operator
    fi
    
    # Check dashboard route
    echo ""
    DASHBOARD_ROUTE=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    if [[ -n "$DASHBOARD_ROUTE" ]]; then
        echo "✅ Dashboard available at: https://$DASHBOARD_ROUTE"
    else
        echo "⏳ Dashboard route not ready yet"
    fi
else
    echo "❌ OpenShift AI Operator NOT installed - GitOps should handle this"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "5️⃣  FIXING GITOPS CONSOLE JOB IF NEEDED"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if oc get job job-gitops-console-plugin -n openshift-gitops &>/dev/null 2>&1; then
    echo "⚠️  GitOps console job exists - Deleting to allow resync..."
    oc delete job job-gitops-console-plugin -n openshift-gitops --ignore-not-found=true
    oc delete pods -n openshift-gitops -l job-name=job-gitops-console-plugin --ignore-not-found=true
    echo "✅ Deleted GitOps console job"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "6️⃣  SYNCING GITOPS APPLICATIONS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Sync key applications
for app in openshift-gitops-operator openshift-ai-operator openshift-servicemesh-operator openshift-serverless-operator; do
    if oc get application $app -n openshift-gitops &>/dev/null 2>&1; then
        echo "Syncing $app..."
        oc annotate application $app -n openshift-gitops argocd.argoproj.io/refresh=normal --overwrite
        oc patch application $app -n openshift-gitops --type=merge \
            -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","prune":true,"syncOptions":["Replace=true"]}}}'
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 FINAL STATUS CHECK"
echo "═══════════════════════════════════════════════════════════════"
echo ""

sleep 10

echo "GitOps Applications Status:"
oc get applications -n openshift-gitops | grep -E "(NAME|openshift-ai|servicemesh|serverless|gitops)" || true

echo ""
echo "Service Mesh Status:"
oc get smcp -n istio-system 2>/dev/null || echo "No SMCP found"

echo ""
echo "Knative Status:"
oc get knativeserving -n knative-serving 2>/dev/null || echo "No KnativeServing found"

echo ""
echo "DataScienceCluster Status:"
oc get datasciencecluster -n redhat-ods-operator 2>/dev/null || echo "No DSC found"

echo ""
echo "✅ Check and fix completed!"
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for all resources to reconcile"
echo "2. Check the OpenShift AI dashboard"
echo "3. Verify model serving is available"
echo ""
echo "To monitor progress:"
echo "  watch 'oc get applications -n openshift-gitops | grep -v Synced'"
