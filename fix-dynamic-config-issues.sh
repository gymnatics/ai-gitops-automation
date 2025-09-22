#!/bin/bash
set -e

echo "🔧 Fixing Dynamic Configuration Issues"
echo "====================================="

# Check current directory
if [[ ! -f "bootstrap.sh" ]]; then
    echo "❌ Error: Must run from ai-gitops-automation root directory"
    exit 1
fi

echo ""
echo "1️⃣ Fixing GPU instance type configuration..."

# Create a proper patch for GPU instance type
mkdir -p components/operators/gpu-operator-certified/instance/overlays/g5-4xlarge

cat > components/operators/gpu-operator-certified/instance/overlays/g5-4xlarge/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

components:
  - ../../components/aws-gpu-machineset

patches:
  - target:
      kind: Job
      name: job-aws-gpu-machineset
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: "g5.4xlarge"
      - op: replace
        path: /spec/template/spec/containers/0/env/2/value
        value: "1"
EOF

echo "✅ Created g5.4xlarge overlay"

echo ""
echo "2️⃣ Fixing AnythingLLM deployment..."

# Check if AnythingLLM patches were created
if [[ ! -f "clusters/overlays/dynamic/patch-tenants-list.yaml" ]]; then
    echo "Creating AnythingLLM tenant patch..."
    
    mkdir -p clusters/overlays/dynamic
    cat > clusters/overlays/dynamic/patch-tenants-list.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenants
spec:
  generators:
  - list:
      elements:
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: anythingllm
          path: tenants/anythingllm/overlays/dynamic
EOF
    
    # Update kustomization to include the patch
    if ! grep -q "patch-tenants-list.yaml" clusters/overlays/dynamic/kustomization.yaml; then
        echo "- target:" >> clusters/overlays/dynamic/kustomization.yaml
        echo "    kind: ApplicationSet" >> clusters/overlays/dynamic/kustomization.yaml
        echo "    name: tenants" >> clusters/overlays/dynamic/kustomization.yaml
        echo "  path: patch-tenants-list.yaml" >> clusters/overlays/dynamic/kustomization.yaml
    fi
fi

# Create AnythingLLM dynamic overlay if it doesn't exist
if [[ ! -d "tenants/anythingllm/overlays/dynamic" ]]; then
    echo "Creating AnythingLLM dynamic overlay..."
    mkdir -p tenants/anythingllm/overlays/dynamic
    
    cat > tenants/anythingllm/overlays/dynamic/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: anythingllm

resources:
  - ../../base

patches:
  - target:
      kind: Job
      name: model-download
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: quay.io/redhat-ai-services/modelcar-catalog:llama3.1-8b
  - target:
      kind: InferenceService
      name: llm-model
    patch: |-
      - op: replace
        path: /metadata/annotations/modelcar.model
        value: llama3.1-8b
  - target:
      kind: Notebook
      name: anythingllm-workbench
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: MODEL_NAME
          value: llama3.1-8b
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: MODEL_ENDPOINT
          value: http://llm-model.anythingllm.svc.cluster.local:8080/v1
EOF
fi

echo "✅ AnythingLLM configuration created"

echo ""
echo "3️⃣ Updating GPU operator path in patch-operators-list.yaml..."

# Update the GPU operator path to use the correct overlay
if [[ -f "clusters/overlays/dynamic/patch-operators-list.yaml" ]]; then
    sed -i.bak 's|path: components/operators/gpu-operator-certified/aggregate/overlays/aws|path: components/operators/gpu-operator-certified/instance/overlays/g5-4xlarge|' clusters/overlays/dynamic/patch-operators-list.yaml
    
    # Also fix the OpenShift AI path to use stable
    sed -i.bak 's|path: components/operators/openshift-ai/aggregate/overlays/eus-2.16-nvidia-gpu|path: components/operators/openshift-ai/aggregate/overlays/stable-nvidia-gpu|' clusters/overlays/dynamic/patch-operators-list.yaml
    
    rm -f clusters/overlays/dynamic/patch-operators-list.yaml.bak
fi

echo ""
echo "4️⃣ Summary of fixes:"
echo "   - Created GPU instance overlay for g5.4xlarge"
echo "   - Created AnythingLLM tenant patches"
echo "   - Updated operator paths to use correct overlays"
echo ""
echo "✅ Fixes applied!"
echo ""
echo "Next steps:"
echo "1. Review the changes:"
echo "   git status"
echo ""
echo "2. Commit and push the fixes:"
echo "   git add -A"
echo "   git commit -m 'Fix dynamic config for GPU instance and AnythingLLM deployment'"
echo "   git push"
echo ""
echo "3. If already deployed, sync the applications:"
echo "   oc patch application nvidia-gpu-operator -n openshift-gitops --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{\"revision\":\"HEAD\"}}}'"
echo "   oc patch application openshift-ai-operator -n openshift-gitops --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{\"revision\":\"HEAD\"}}}'"
echo "   oc patch applicationset tenants -n openshift-gitops --type merge -p '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"normal\"}}}'"
