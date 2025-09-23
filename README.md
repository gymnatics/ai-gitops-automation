# Red Hat AI Infrastructure GitOps

Welcome to the Red Hat AI Infrastructure GitOps project\! This project is a fork of the upstream [AI Accelerator project](https://github.com/redhat-ai-services/ai-accelerator) and is designed to deploy all of the required cluster components for AI Workloads to an OpenShift cluster.

![AI Accelerator Overview](documentation/diagrams/AI_Accelerator.drawio.png)

## Installation

### Prerequisites

- Openshift 4.16+ cluster

> [!IMPORTANT]  
> There is a known issue with using Kubernetes version 4.17 in relation to the Node Feature Discovery Operator, which causes issues allocating nodes that use GPUs. It is recommended to avoid this version for now.

### Quick Start

Installation can be done using `./bootstrap.sh` script.

> [!TIP]  
> First time installs it is recommended to allow the script to walk through options, but future runs can be automated using cli flags, run `./bootstrap.sh --help` for more information.

#### Interactive Mode

Run `./bootstrap.sh` without any flags to enter interactive mode, which will guide you through:
- Cluster overlay selection (or dynamic configuration)
- Operator version selection
- GPU configuration options
- AnythingLLM deployment
- Custom sizing options

#### Dynamic Configuration (New!)

The bootstrap script now supports dynamic configuration of operator versions and instance types. You can either:

1. **Interactive Mode**: Run `./bootstrap.sh` and select option 2 for dynamic configuration
2. **CLI Mode**: Use command-line flags to specify configurations

##### Example CLI Usage

```bash
# Basic dynamic configuration with GPU support
./bootstrap.sh --dynamic --enable-gpu --gpu-instance=g5.4xlarge --gpu-replicas=2

# Full configuration with stable OpenShift AI
./bootstrap.sh --non-interactive --dynamic \
  --gitops-version=latest \
  --ai-version=stable \
  --gpu-operator-version=v24.9 \
  --pipelines-version=stable \
  --serverless-version=stable \
  --servicemesh-version=2.6 \
  --enable-gpu \
  --gpu-instance=g5.4xlarge \
  --gpu-replicas=3 \
  --custom-notebook-sizes \
  --custom-model-sizes

# Deploy with AnythingLLM and ModelCar
./bootstrap.sh --non-interactive --dynamic \
  --ai-version=stable \
  --enable-gpu \
  --gpu-instance=g5.4xlarge \
  --enable-anythingllm \
  --modelcar-model=llama3.1-8b
```

##### Available Options

**Operator Versions:**
- `--gitops-version`: OpenShift GitOps (latest, gitops-1.13, gitops-1.12, etc.)
- `--ai-version`: OpenShift AI (stable, stable-2.16, eus-2.16, fast, beta)
- `--gpu-operator-version`: NVIDIA GPU Operator (stable, v24.9, v24.6, v23.9, etc.)
- `--nfd-version`: Node Feature Discovery (stable, 4.17, 4.16, 4.15)
- `--pipelines-version`: OpenShift Pipelines (latest, stable, pipelines-1.15, etc.)
- `--serverless-version`: OpenShift Serverless (stable, 1.34, 1.33, 1.32)
- `--servicemesh-version`: Service Mesh (stable, 2.6, 2.5, 2.4)

**GPU Configuration:**
- `--enable-gpu`: Enable GPU support
- `--gpu-instance`: GPU instance type (g4dn.4xlarge, g5.xlarge, p3.2xlarge, etc.)
- `--gpu-replicas`: Number of GPU nodes (default: 1)

**Instance Sizes:**
- `--custom-notebook-sizes`: Use custom notebook pod sizes
- `--custom-model-sizes`: Use custom model server pod sizes

**AnythingLLM Configuration:**
- `--enable-anythingllm`: Deploy AnythingLLM tenant application
- `--modelcar-model`: ModelCar model to use (llama3-8b, llama3.1-8b, mistral-7b, etc.)

## Additional Documentation and Info

* [Overview](documentation/overview.md) - what's inside this repository?
* [Installation Guide](documentation/installation.md) - containing step by step instructions for executing this installation sequence on your cluster
* [Dynamic Configuration](documentation/dynamic-configuration.md) - detailed guide on using dynamic operator and instance configuration

### Operators

* [Authorino Operator](components/operators/authorino-operator/)
* [NVIDIA GPU Operator](components/operators/gpu-operator-certified/) - Supports versions: stable, v24.9, v24.6, v23.9, v23.6, v23.3, v22.9
* [Node Feature Discovery Operator](components/operators/nfd/) - Supports versions: stable, 4.17, 4.16, 4.15
* [OpenShift AI](components/operators/openshift-ai/) - Supports versions: stable, stable-2.16, eus-2.16, stable-2.13, stable-2.10, fast, beta
* [OpenShift Pipelines](components/operators/openshift-pipelines/) - Supports versions: latest, stable, pipelines-1.15, pipelines-1.14, pipelines-1.13
* [OpenShift Serverless](components/operators/openshift-serverless/) - Supports versions: stable, 1.34, 1.33, 1.32
* [OpenShift ServiceMesh](components/operators/openshift-servicemesh/) - Supports versions: stable, 2.6, 2.5, 2.4

### Applications

* OpenShift GitOps: [ArgoCD](components/argocd/)
* S3 compatible storage: [MinIO](components/apps/minio)

### Configuration

* [Bootstrap Overlays](bootstrap/overlays/)
* [Cluster Configuration Sets](clusters/overlays/)

### Tenants

* [Tenant Examples](tenants/)
* [AnythingLLM](tenants/anythingllm/) - RAG application with GPU-accelerated LLM inference

## Utility Scripts

The `scripts/` directory contains various utility scripts for cluster management:

### Verification and Fixes
* `verify-bootstrap.sh` - Verify GitOps installation and application status
* `check-cluster-status.sh` - Comprehensive cluster status check
* `check-and-fix-cluster.sh` - Automatically fix common cluster issues
* `fix-gitops-console-job.sh` - Fix GitOps console plugin job issues
* `fix-dynamic-config-issues.sh` - Fix dynamic configuration issues
* `fix-and-test-cluster.sh` - Combined fix and test script
* `test-fix.sh` - Test fixes after applying

### Cleanup Scripts
* `pre-cleanup-check.sh` - Show what would be removed before cleanup
* `cleanup-cluster.sh` - Remove all GitOps-managed resources and return cluster to bare state

> [!WARNING]  
> The cleanup script will remove ALL installed operators, applications, and configurations. Use with caution!
