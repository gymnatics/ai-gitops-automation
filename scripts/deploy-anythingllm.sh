#!/bin/bash
set -e

# Default values
MODELCAR_MODEL="${MODELCAR_MODEL:-qwen3-8b}"
NAMESPACE="anythingllm"
DRY_RUN="${DRY_RUN:-false}"

# Show help
function show_help {
  echo "Usage: $0 [OPTIONS]"
  echo "Deploy AnythingLLM tenant to existing OpenShift AI cluster"
  echo ""
  echo "Options:"
  echo "  --model=<model>     Model to deploy from modelcar catalog (default: qwen3-8b)"
  echo "  --namespace=<ns>    Namespace to deploy to (default: anythingllm)"
  echo "  --dry-run          Show what would be deployed without applying"
  echo "  --help             Show this help message"
  echo ""
  echo "Available models:"
  echo "  - qwen3-8b"
  echo "  - llama3.1-8b"
  echo "  - mistral-7b"
  echo "  - phi-3-mini"
}

# Parse arguments
for arg in "$@"
do
  case $arg in
    --model=*)
      MODELCAR_MODEL="${arg#*=}"
      shift
    ;;
    --namespace=*)
      NAMESPACE="${arg#*=}"
      shift
    ;;
    --dry-run)
      DRY_RUN="true"
      shift
    ;;
    --help)
      show_help
      exit 0
    ;;
  esac
done

echo "🚀 Deploying AnythingLLM with model: ${MODELCAR_MODEL}"
echo "📦 Target namespace: ${NAMESPACE}"

# Check if logged in to OpenShift
if ! oc whoami &>/dev/null; then
    echo "❌ Error: Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

# Check if OpenShift AI is installed
if ! oc get csv -n redhat-ods-operator | grep -q "rhods-operator.*Succeeded"; then
    echo "❌ Error: OpenShift AI operator not found or not ready."
    echo "Please ensure OpenShift AI is installed and running."
    exit 1
fi

# Create temporary directory for manifests
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Create dynamic overlay
echo "📝 Creating dynamic configuration..."
mkdir -p "${TEMP_DIR}/anythingllm"

# Copy base resources
cp -r tenants/anythingllm/base/* "${TEMP_DIR}/anythingllm/"

# Update namespace if different from default
if [[ "${NAMESPACE}" != "anythingllm" ]]; then
  find "${TEMP_DIR}/anythingllm" -name "*.yaml" -type f -exec sed -i '' "s/namespace: anythingllm/namespace: ${NAMESPACE}/g" {} \;
  sed -i '' "s/name: anythingllm/name: ${NAMESPACE}/g" "${TEMP_DIR}/anythingllm/namespace.yaml"
fi

# Update model references
sed -i '' "s|quay.io/redhat-ai-services/modelcar-catalog:qwen3-8b|quay.io/redhat-ai-services/modelcar-catalog:${MODELCAR_MODEL}|g" "${TEMP_DIR}/anythingllm/model-download-job.yaml"
sed -i '' "s|modelcar.model: \"qwen3-8b\"|modelcar.model: \"${MODELCAR_MODEL}\"|g" "${TEMP_DIR}/anythingllm/inferenceservice.yaml"

# Add model info to workbench
cat >> "${TEMP_DIR}/anythingllm/workbench.yaml" <<EOF
          - name: MODEL_NAME
            value: "${MODELCAR_MODEL}"
          - name: MODEL_ENDPOINT
            value: "http://llm-model.${NAMESPACE}.svc.cluster.local:8080/v1"
EOF

if [[ "${DRY_RUN}" == "true" ]]; then
  echo ""
  echo "🔍 Dry run mode - showing what would be deployed:"
  echo "=================================================="
  kustomize build "${TEMP_DIR}/anythingllm" | oc apply --dry-run=client -f -
else
  echo ""
  echo "📋 Applying AnythingLLM resources..."
  
  # Apply the resources
  kustomize build "${TEMP_DIR}/anythingllm" | oc apply -f -
  
  echo ""
  echo "⏳ Waiting for namespace to be ready..."
  oc wait --for=condition=Active namespace/${NAMESPACE} --timeout=60s || true
  
  echo ""
  echo "📊 Deployment status:"
  echo "===================="
  oc get all -n ${NAMESPACE}
  
  echo ""
  echo "✅ AnythingLLM deployment initiated!"
  echo ""
  echo "Monitor the deployment with:"
  echo "  oc get pods -n ${NAMESPACE} -w"
  echo ""
  echo "Check workbench status:"
  echo "  oc get notebook -n ${NAMESPACE}"
  echo ""
  echo "Check model serving status:"
  echo "  oc get inferenceservice -n ${NAMESPACE}"
fi
