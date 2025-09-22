#!/bin/bash
set -e

# Default values
NAMESPACE="${NAMESPACE:-anythingllm}"
FORCE="${FORCE:-false}"

# Show help
function show_help {
  echo "Usage: $0 [OPTIONS]"
  echo "Remove AnythingLLM deployment from cluster"
  echo ""
  echo "Options:"
  echo "  --namespace=<ns>    Namespace to clean up (default: anythingllm)"
  echo "  --force            Skip confirmation prompt"
  echo "  --help             Show this help message"
}

# Parse arguments
for arg in "$@"
do
  case $arg in
    --namespace=*)
      NAMESPACE="${arg#*=}"
      shift
    ;;
    --force)
      FORCE="true"
      shift
    ;;
    --help)
      show_help
      exit 0
    ;;
  esac
done

echo "🧹 AnythingLLM Cleanup Script"
echo "============================"
echo "Target namespace: ${NAMESPACE}"
echo ""

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo "❌ Error: Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

# Check if namespace exists
if ! oc get namespace ${NAMESPACE} &>/dev/null 2>&1; then
    echo "ℹ️  Namespace ${NAMESPACE} does not exist. Nothing to clean up."
    exit 0
fi

# Show what will be deleted
echo "Resources to be deleted:"
echo "----------------------"
oc get all,pvc,secrets,cm,notebook,servingruntime,inferenceservice -n ${NAMESPACE} 2>/dev/null | tail -n +2 || true

# Confirmation
if [[ "${FORCE}" != "true" ]]; then
    echo ""
    read -p "⚠️  Are you sure you want to delete these resources? (yes/no): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

echo ""
echo "🗑️  Deleting resources..."

# Delete InferenceService first (it has finalizers)
echo "Deleting InferenceService..."
oc delete inferenceservice --all -n ${NAMESPACE} --timeout=60s 2>/dev/null || true

# Delete ServingRuntime
echo "Deleting ServingRuntime..."
oc delete servingruntime --all -n ${NAMESPACE} --timeout=30s 2>/dev/null || true

# Delete Notebook
echo "Deleting Notebook..."
oc delete notebook --all -n ${NAMESPACE} --timeout=30s 2>/dev/null || true

# Delete remaining resources
echo "Deleting other resources..."
oc delete all --all -n ${NAMESPACE} --timeout=30s 2>/dev/null || true

# Delete PVCs
echo "Deleting PVCs..."
oc delete pvc --all -n ${NAMESPACE} --timeout=30s 2>/dev/null || true

# Delete namespace
echo "Deleting namespace..."
oc delete namespace ${NAMESPACE} --timeout=60s

echo ""
echo "✅ Cleanup complete!"

# If GitOps is managing this, remove from ApplicationSet
if oc get applicationset tenants -n openshift-gitops &>/dev/null 2>&1; then
    echo ""
    echo "ℹ️  Note: If this was deployed via GitOps, you may need to:"
    echo "   1. Remove the AnythingLLM entry from the tenants ApplicationSet"
    echo "   2. Or update the ApplicationSet patch file"
fi
