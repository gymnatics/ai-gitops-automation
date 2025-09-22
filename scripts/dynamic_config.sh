#!/bin/bash
set -e

# Dynamic Configuration Functions for AI GitOps Automation

CONFIG_DIR="$(dirname "$0")/config"
OPERATOR_CONFIG="${CONFIG_DIR}/operator-versions.yaml"
INSTANCE_CONFIG="${CONFIG_DIR}/instance-types.yaml"
DYNAMIC_OVERLAY_DIR="bootstrap/overlays/dynamic"

# Function to parse YAML and get operator versions
get_operator_versions() {
    local operator=$1
    yq eval ".operators.${operator}.versions[].name" "${OPERATOR_CONFIG}" 2>/dev/null || echo ""
}

# Function to get default operator version
get_default_operator_version() {
    local operator=$1
    yq eval ".operators.${operator}.default" "${OPERATOR_CONFIG}" 2>/dev/null || echo "stable"
}

# Function to get operator channel for a version
get_operator_channel() {
    local operator=$1
    local version=$2
    yq eval ".operators.${operator}.versions[] | select(.name == \"${version}\") | .channel" "${OPERATOR_CONFIG}" 2>/dev/null || echo "${version}"
}

# Function to get GPU instance types
get_gpu_instance_types() {
    yq eval '.gpu_instances.aws.types[].name' "${INSTANCE_CONFIG}" 2>/dev/null || echo "g4dn.4xlarge"
}

# Function to get default GPU instance type
get_default_gpu_instance() {
    yq eval '.gpu_instances.aws.types[] | select(.default == true) | .name' "${INSTANCE_CONFIG}" 2>/dev/null || echo "g4dn.4xlarge"
}

# Function to get notebook sizes
get_notebook_sizes() {
    yq eval '.notebook_sizes.sizes[].name' "${INSTANCE_CONFIG}" 2>/dev/null || echo "Medium"
}

# Function to get model server sizes
get_model_server_sizes() {
    yq eval '.model_server_sizes.sizes[].name' "${INSTANCE_CONFIG}" 2>/dev/null || echo "Small"
}

# Function to create dynamic overlay
create_dynamic_overlay() {
    echo "📦 Creating dynamic overlay configuration..."
    
    # Create dynamic overlay directory
    if [[ "${DRY_RUN}" != "true" ]]; then
        mkdir -p "${DYNAMIC_OVERLAY_DIR}"
    fi
    
    # Create base kustomization
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "Would create: ${DYNAMIC_OVERLAY_DIR}/kustomization.yaml"
    else
        cat > "${DYNAMIC_OVERLAY_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base
- ../../../clusters/overlays/dynamic
EOF
    fi
}

# Function to create dynamic cluster overlay
create_dynamic_cluster_overlay() {
    local cluster_overlay_dir="clusters/overlays/dynamic"
    mkdir -p "${cluster_overlay_dir}"
    
    # Create base kustomization for cluster
    cat > "${cluster_overlay_dir}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

patches:
- target:
    kind: Application
  path: patch-application-repo-revision.yaml
- target:
    kind: Application
  path: patch-application-manual-sync.yaml
- target:
    kind: ApplicationSet
  path: patch-applicationset-manual-sync.yaml
- target:
    kind: ApplicationSet
    name: cluster-operators
  path: patch-operators-list.yaml
EOF

    # Copy manual sync patches from aws-open-environment
    cp clusters/overlays/aws-open-environment/patch-application-manual-sync.yaml "${cluster_overlay_dir}/"
    cp clusters/overlays/aws-open-environment/patch-application-repo-revision.yaml "${cluster_overlay_dir}/"
    cp clusters/overlays/aws-open-environment/patch-applicationset-manual-sync.yaml "${cluster_overlay_dir}/"
}

# Function to create operator patches
create_operator_patches() {
    local cluster_overlay_dir="clusters/overlays/dynamic"
    
    # Get operator versions from environment or use defaults
    local gitops_version="${GITOPS_VERSION:-$(get_default_operator_version 'openshift-gitops')}"
    local ai_version="${OPENSHIFT_AI_VERSION:-$(get_default_operator_version 'openshift-ai')}"
    local gpu_version="${GPU_OPERATOR_VERSION:-$(get_default_operator_version 'gpu-operator')}"
    local nfd_version="${NFD_VERSION:-$(get_default_operator_version 'nfd')}"
    local pipelines_version="${PIPELINES_VERSION:-$(get_default_operator_version 'openshift-pipelines')}"
    local serverless_version="${SERVERLESS_VERSION:-$(get_default_operator_version 'openshift-serverless')}"
    local servicemesh_version="${SERVICEMESH_VERSION:-$(get_default_operator_version 'openshift-servicemesh')}"
    local elasticsearch_version="${ELASTICSEARCH_VERSION:-$(get_default_operator_version 'elasticsearch')}"
    local authorino_version="${AUTHORINO_VERSION:-$(get_default_operator_version 'authorino')}"
    
    # Determine AI overlay based on GPU support
    local ai_overlay="eus-2.16"
    if [[ "${ENABLE_GPU}" == "true" ]]; then
        ai_overlay="eus-2.16-nvidia-gpu"
    fi
    
    # Override if specific version requested
    if [[ "${ai_version}" != "eus-2.16" ]]; then
        ai_overlay="${ai_version}"
        if [[ "${ENABLE_GPU}" == "true" ]]; then
            ai_overlay="${ai_version}-nvidia-gpu"
        fi
    fi
    
    # Create operator list patch
    cat > "${cluster_overlay_dir}/patch-operators-list.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-operators
spec:
  generators:
  - list:
      elements:
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: authorino-operator
          path: components/operators/authorino-operator/operator/overlays/${authorino_version}
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: elasticsearch-operator
          path: components/operators/elasticsearch/operator/overlays/${elasticsearch_version}
EOF

    # Add GPU operator if enabled
    if [[ "${ENABLE_GPU}" == "true" ]]; then
        cat >> "${cluster_overlay_dir}/patch-operators-list.yaml" <<EOF
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: nvidia-gpu-operator
          path: components/operators/gpu-operator-certified/aggregate/overlays/aws
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: nfd-operator
          path: components/operators/nfd/aggregate/overlays/default
EOF
    fi
    
    # Continue with other operators
    cat >> "${cluster_overlay_dir}/patch-operators-list.yaml" <<EOF
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: openshift-ai-operator
          path: components/operators/openshift-ai/aggregate/overlays/${ai_overlay}
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: openshift-gitops-operator
          path: components/operators/openshift-gitops/aggregate/overlays/default
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: openshift-pipelines-operator
          path: components/operators/openshift-pipelines/operator/overlays/${pipelines_version}
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: openshift-serverless-operator
          path: components/operators/openshift-serverless/operator/overlays/${serverless_version}
      - cluster: local
        url: https://kubernetes.default.svc
        values:
          name: openshift-servicemesh-operator
          path: components/operators/openshift-servicemesh/operator/overlays/${servicemesh_version}
EOF

    # Add AnythingLLM tenant if enabled
    if [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]; then
        # Create tenant patch file
        create_anythingllm_patches
    fi
}

# Function to create instance type patches
create_instance_patches() {
    local components_dir="components/operators"
    
    # GPU Instance configuration
    if [[ "${ENABLE_GPU}" == "true" ]] && [[ -n "${GPU_INSTANCE_TYPE}" ]]; then
        echo "🖥️  Configuring GPU instance type: ${GPU_INSTANCE_TYPE}"
        
        # Update the GPU machineset job environment
        local gpu_job_file="${components_dir}/gpu-operator-certified/instance/components/aws-gpu-machineset/job.yaml"
        if [[ -f "${gpu_job_file}" ]]; then
            yq eval -i ".spec.template.spec.containers[0].env[] |= (select(.name == \"INSTANCE_TYPE\").value = \"${GPU_INSTANCE_TYPE}\")" "${gpu_job_file}"
            
            # Update replicas if specified
            if [[ -n "${GPU_REPLICAS}" ]]; then
                yq eval -i ".spec.template.spec.containers[0].env[] |= (select(.name == \"REPLICAS\").value = \"${GPU_REPLICAS}\")" "${gpu_job_file}"
            fi
        fi
    fi
    
    # Notebook sizes configuration
    if [[ "${CUSTOM_NOTEBOOK_SIZES}" == "true" ]]; then
        echo "📓 Configuring custom notebook sizes..."
        create_notebook_sizes_patch
    fi
    
    # Model server sizes configuration
    if [[ "${CUSTOM_MODEL_SIZES}" == "true" ]]; then
        echo "🤖 Configuring custom model server sizes..."
        create_model_server_sizes_patch
    fi
}

# Function to create notebook sizes patch
create_notebook_sizes_patch() {
    local patch_file="components/operators/openshift-ai/instance/components/notebook-pod-sizes/patch-rhoai-dashboard.yaml"
    
    # Get notebook sizes from config
    local sizes=$(yq eval -o=json '.notebook_sizes.sizes' "${INSTANCE_CONFIG}")
    
    cat > "${patch_file}" <<EOF
- op: replace
  path: /spec/notebookSizes
  value:
EOF
    
    echo "${sizes}" | yq eval -P '.' - >> "${patch_file}"
}

# Function to create model server sizes patch
create_model_server_sizes_patch() {
    local patch_file="components/operators/openshift-ai/instance/components/model-server-pod-sizes/patch-rhoai-dashboard.yaml"
    
    # Get model server sizes from config
    local sizes=$(yq eval -o=json '.model_server_sizes.sizes' "${INSTANCE_CONFIG}")
    
    cat > "${patch_file}" <<EOF
- op: replace
  path: /spec/dashboardConfig/modelServerSizes
  value:
EOF
    
    echo "${sizes}" | yq eval -P '.' - >> "${patch_file}"
}

# Function to create AnythingLLM patches
create_anythingllm_patches() {
    local model_name="${MODELCAR_MODEL:-qwen3-8b}"
    local anythingllm_overlay_dir="tenants/anythingllm/overlays/dynamic"
    
    echo "🤖 Configuring AnythingLLM with model: ${model_name}"
    
    # Create overlay directory
    mkdir -p "${anythingllm_overlay_dir}"
    
    # Create kustomization for dynamic overlay
    cat > "${anythingllm_overlay_dir}/kustomization.yaml" <<EOF
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
        value: quay.io/redhat-ai-services/modelcar-catalog:${model_name}
  - target:
      kind: InferenceService
      name: llm-model
    patch: |-
      - op: replace
        path: /metadata/annotations/modelcar.model
        value: ${model_name}
  - target:
      kind: Notebook
      name: anythingllm-workbench
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: MODEL_NAME
          value: ${model_name}
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: MODEL_ENDPOINT
          value: http://llm-model.anythingllm.svc.cluster.local:8080/v1
EOF
    
    # Update tenants ApplicationSet patch to include AnythingLLM
    local tenants_patch="clusters/overlays/dynamic/patch-tenants-list.yaml"
    cat > "${tenants_patch}" <<EOF
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
}

# Function to prompt for operator versions
prompt_operator_versions() {
    echo
    echo "🔧 Configure Operator Versions"
    echo "==============================="
    
    # OpenShift GitOps
    local gitops_versions=($(get_operator_versions "openshift-gitops"))
    local default_gitops=$(get_default_operator_version "openshift-gitops")
    if [[ ${#gitops_versions[@]} -gt 0 ]]; then
        echo
        echo "OpenShift GitOps version:"
        PS3="Select GitOps version (default: ${default_gitops}): "
        select version in "${gitops_versions[@]}" "Use default (${default_gitops})"; do
            if [[ "$version" == "Use default (${default_gitops})" ]] || [[ -z "$version" ]]; then
                export GITOPS_VERSION="${default_gitops}"
            else
                export GITOPS_VERSION="${version}"
            fi
            break
        done
    fi
    
    # OpenShift AI
    local ai_versions=($(get_operator_versions "openshift-ai"))
    local default_ai=$(get_default_operator_version "openshift-ai")
    if [[ ${#ai_versions[@]} -gt 0 ]]; then
        echo
        echo "OpenShift AI version:"
        PS3="Select OpenShift AI version (default: ${default_ai}): "
        select version in "${ai_versions[@]}" "Use default (${default_ai})"; do
            if [[ "$version" == "Use default (${default_ai})" ]] || [[ -z "$version" ]]; then
                export OPENSHIFT_AI_VERSION="${default_ai}"
            else
                export OPENSHIFT_AI_VERSION="${version}"
            fi
            break
        done
    fi
    
    # Similar prompts for other operators...
    echo
    echo "✅ Operator versions configured"
}

# Function to prompt for instance types
prompt_instance_types() {
    echo
    echo "🖥️  Configure Instance Types"
    echo "============================="
    
    # GPU Support
    echo
    read -p "Enable GPU support? (y/N): " enable_gpu
    if [[ "${enable_gpu,,}" == "y" ]]; then
        export ENABLE_GPU="true"
        
        # GPU Instance Type
        local gpu_types=($(get_gpu_instance_types))
        local default_gpu=$(get_default_gpu_instance)
        echo
        echo "GPU Instance Type:"
        PS3="Select GPU instance type (default: ${default_gpu}): "
        select gpu_type in "${gpu_types[@]}" "Use default (${default_gpu})"; do
            if [[ "$gpu_type" == "Use default (${default_gpu})" ]] || [[ -z "$gpu_type" ]]; then
                export GPU_INSTANCE_TYPE="${default_gpu}"
            else
                export GPU_INSTANCE_TYPE="${gpu_type}"
            fi
            break
        done
        
        # GPU Replicas
        echo
        read -p "Number of GPU nodes (default: 1): " gpu_replicas
        export GPU_REPLICAS="${gpu_replicas:-1}"
    else
        export ENABLE_GPU="false"
    fi
    
    # Custom notebook sizes
    echo
    read -p "Use custom notebook sizes? (y/N): " custom_notebooks
    if [[ "${custom_notebooks,,}" == "y" ]]; then
        export CUSTOM_NOTEBOOK_SIZES="true"
    else
        export CUSTOM_NOTEBOOK_SIZES="false"
    fi
    
    # Custom model server sizes
    echo
    read -p "Use custom model server sizes? (y/N): " custom_models
    if [[ "${custom_models,,}" == "y" ]]; then
        export CUSTOM_MODEL_SIZES="true"
    else
        export CUSTOM_MODEL_SIZES="false"
    fi
    
    # AnythingLLM deployment
    echo
    read -p "Deploy AnythingLLM with model serving? (y/N): " deploy_anythingllm
    if [[ "${deploy_anythingllm,,}" == "y" ]]; then
        export ENABLE_ANYTHINGLLM="true"
        
        # Model selection
        echo
        echo "Available models from modelcar catalog:"
        echo "1) qwen3-8b"
        echo "2) llama3.1-8b"
        echo "3) mistral-7b"
        echo "4) phi-3-mini"
        echo "5) Custom (enter model tag)"
        
        read -p "Select model (1-5): " model_choice
        case $model_choice in
            1) export MODELCAR_MODEL="qwen3-8b" ;;
            2) export MODELCAR_MODEL="llama3.1-8b" ;;
            3) export MODELCAR_MODEL="mistral-7b" ;;
            4) export MODELCAR_MODEL="phi-3-mini" ;;
            5) 
                read -p "Enter custom model tag: " custom_model
                export MODELCAR_MODEL="${custom_model}"
                ;;
            *) export MODELCAR_MODEL="qwen3-8b" ;;
        esac
    else
        export ENABLE_ANYTHINGLLM="false"
    fi
    
    echo
    echo "✅ Instance types configured"
}

# Function to apply dynamic configuration
apply_dynamic_config() {
    echo
    echo "🚀 Applying Dynamic Configuration"
    echo "================================="
    
    # Create overlays
    create_dynamic_overlay
    create_dynamic_cluster_overlay
    
    # Create patches
    create_operator_patches
    create_instance_patches
    
    echo
    echo "✅ Dynamic configuration created successfully!"
    echo
    echo "Configuration Summary:"
    echo "---------------------"
    echo "GitOps Version: ${GITOPS_VERSION:-default}"
    echo "OpenShift AI Version: ${OPENSHIFT_AI_VERSION:-default}"
    echo "GPU Enabled: ${ENABLE_GPU:-false}"
    if [[ "${ENABLE_GPU}" == "true" ]]; then
        echo "GPU Instance Type: ${GPU_INSTANCE_TYPE}"
        echo "GPU Replicas: ${GPU_REPLICAS:-1}"
    fi
    echo "Custom Notebook Sizes: ${CUSTOM_NOTEBOOK_SIZES:-false}"
    echo "Custom Model Server Sizes: ${CUSTOM_MODEL_SIZES:-false}"
    echo "AnythingLLM Enabled: ${ENABLE_ANYTHINGLLM:-false}"
    if [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]; then
        echo "Model: ${MODELCAR_MODEL:-qwen3-8b}"
    fi
    echo
    
    # Set bootstrap directory to dynamic
    export BOOTSTRAP_DIR="dynamic"
}
