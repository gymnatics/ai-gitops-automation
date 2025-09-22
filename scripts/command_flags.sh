# Help function
function show_help {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --ocp_version=4.11    Target Openshift Version"
  echo "  --bootstrap_dir=<bootstrap_directory>    Base folder inside of bootstrap/overlays (Optional, pick during script execution if not set)"
  echo "  --timeout=45          Timeout in seconds for waiting for each resource to be ready"
  echo "  -f                    If set, will update the \`patch-application-repo-revision\` folder inside of your overlay with the current git information and push a checkin"
  echo "  --reset-git           Locally resets changes made by the bootstrap script. Please run and checkin the changes before creating a PR"
  echo "  --non-interactive     Run in non-interactive mode (use defaults)"
  echo ""
  echo "Dynamic Configuration Options:"
  echo "  --dynamic             Use dynamic configuration"
  echo "  --gitops-version=<version>     OpenShift GitOps version (e.g., latest, gitops-1.13)"
  echo "  --ai-version=<version>         OpenShift AI version (e.g., stable, eus-2.16)"
  echo "  --gpu-operator-version=<version>  GPU Operator version (e.g., stable, v24.9)"
  echo "  --nfd-version=<version>           NFD version (e.g., stable, 4.16)"
  echo "  --pipelines-version=<version>     Pipelines version (e.g., latest, stable)"
  echo "  --serverless-version=<version>    Serverless version (e.g., stable, 1.34)"
  echo "  --servicemesh-version=<version>   Service Mesh version (e.g., stable, 2.6)"
  echo "  --enable-gpu          Enable GPU support"
  echo "  --gpu-instance=<type> GPU instance type (e.g., g4dn.4xlarge, p3.2xlarge)"
  echo "  --gpu-replicas=<num>  Number of GPU nodes (default: 1)"
  echo "  --custom-notebook-sizes    Use custom notebook sizes"
  echo "  --custom-model-sizes       Use custom model server sizes"
  echo "  --modelcar-model=<model>   Model to deploy from modelcar catalog (e.g., qwen3-8b)"
  echo "  --enable-anythingllm       Enable AnythingLLM deployment"
  echo "  --help                Show this help message"
}

for arg in "$@"
do
  case $arg in
    --cluster=*)
      export CLUSTER_NAME="${arg#*=}"
      shift
    ;;
    --ocp_version=*)
      export OCP_VERSION="${arg#*=}"
      echo "Using OCP Binaries Version: ${OCP_VERSION}"
      shift
    ;;
    --bootstrap_dir=*)
      export BOOTSTRAP_DIR="${arg#*=}"
      echo "Using Bootstrap Directory: ${BOOTSTRAP_DIR}"
      shift
    ;;
    -f)
      export FORCE=true
      echo "Force set, using current git branch"
      shift
    ;;
    --reset-git)
      source "$(dirname "$0")/reset_git.sh"
      exit 0
    ;;
    --non-interactive)
      export INTERACTIVE="false"
      shift
    ;;
    --dynamic)
      export USE_DYNAMIC="true"
      export BOOTSTRAP_DIR="dynamic"
      shift
    ;;
    --gitops-version=*)
      export GITOPS_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --ai-version=*)
      export OPENSHIFT_AI_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --gpu-operator-version=*)
      export GPU_OPERATOR_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --nfd-version=*)
      export NFD_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --pipelines-version=*)
      export PIPELINES_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --serverless-version=*)
      export SERVERLESS_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --servicemesh-version=*)
      export SERVICEMESH_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --elasticsearch-version=*)
      export ELASTICSEARCH_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --authorino-version=*)
      export AUTHORINO_VERSION="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --enable-gpu)
      export ENABLE_GPU="true"
      export USE_DYNAMIC="true"
      shift
    ;;
    --gpu-instance=*)
      export GPU_INSTANCE_TYPE="${arg#*=}"
      export ENABLE_GPU="true"
      export USE_DYNAMIC="true"
      shift
    ;;
    --gpu-replicas=*)
      export GPU_REPLICAS="${arg#*=}"
      export USE_DYNAMIC="true"
      shift
    ;;
    --custom-notebook-sizes)
      export CUSTOM_NOTEBOOK_SIZES="true"
      export USE_DYNAMIC="true"
      shift
    ;;
    --custom-model-sizes)
      export CUSTOM_MODEL_SIZES="true"
      export USE_DYNAMIC="true"
      shift
    ;;
    --modelcar-model=*)
      export MODELCAR_MODEL="${arg#*=}"
      export ENABLE_ANYTHINGLLM="true"
      export USE_DYNAMIC="true"
      shift
    ;;
    --enable-anythingllm)
      export ENABLE_ANYTHINGLLM="true"
      export USE_DYNAMIC="true"
      shift
    ;;
    --help)
      show_help
      exit 0
    ;;

  esac
done

# If dynamic flags are used, automatically apply dynamic config
if [[ "${USE_DYNAMIC}" == "true" ]] && [[ "${BOOTSTRAP_DIR}" != "dynamic" ]]; then
  export BOOTSTRAP_DIR="dynamic"
  if [[ "${INTERACTIVE}" != "false" ]]; then
    # In non-interactive mode with dynamic flags, skip prompts
    apply_dynamic_config
  fi
fi

