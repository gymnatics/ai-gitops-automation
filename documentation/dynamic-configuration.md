# Dynamic Configuration Guide

This guide explains how to use the dynamic configuration feature in the AI GitOps Automation bootstrap script to customize operator versions and instance types.

## Overview

The dynamic configuration feature allows you to:

1. **Select specific operator versions** - Choose from multiple available versions for each operator
2. **Configure GPU support** - Enable GPU nodes with specific instance types and quantities
3. **Customize pod sizes** - Define custom resource requirements for notebooks and model servers
4. **Automate deployment** - Use CLI flags for fully automated, reproducible deployments

## Interactive Mode

When running `./bootstrap.sh` without flags, you'll be presented with options:

```
Bootstrap Options:
1) Use existing overlay (aws-open-environment, composer-ai-lab, demo.redhat.com)
2) Create dynamic configuration (recommended)

Select option (1-2): 2
```

Selecting option 2 will guide you through:

1. **Operator Version Selection** - Choose versions for each operator
2. **GPU Configuration** - Enable GPU support and select instance types
3. **Resource Customization** - Configure notebook and model server sizes

## Command Line Mode

For automated deployments, use command-line flags:

### Basic Usage

```bash
# Minimal dynamic configuration
./bootstrap.sh --dynamic

# With GPU support
./bootstrap.sh --dynamic --enable-gpu --gpu-instance=g4dn.4xlarge

# Non-interactive with defaults
./bootstrap.sh --non-interactive --dynamic
```

### Advanced Usage

```bash
./bootstrap.sh --non-interactive --dynamic \
  --gitops-version=gitops-1.13 \
  --ai-version=stable-2.16 \
  --gpu-operator-version=v24.9 \
  --nfd-version=4.16 \
  --pipelines-version=pipelines-1.15 \
  --serverless-version=1.34 \
  --servicemesh-version=2.6 \
  --elasticsearch-version=stable-5.8 \
  --authorino-version=managed-services \
  --enable-gpu \
  --gpu-instance=g5.12xlarge \
  --gpu-replicas=4 \
  --custom-notebook-sizes \
  --custom-model-sizes
```

## Configuration Options

### Operator Versions

#### OpenShift GitOps
- `latest` - Latest stable version (default)
- `gitops-1.13` - GitOps 1.13
- `gitops-1.12` - GitOps 1.12
- `gitops-1.11` - GitOps 1.11
- `gitops-1.10` - GitOps 1.10

#### OpenShift AI
- `stable` - Stable channel (default)
- `stable-2.16` - Stable 2.16
- `eus-2.16` - Extended Update Support 2.16
- `stable-2.13` - Stable 2.13
- `stable-2.10` - Stable 2.10
- `fast` - Fast channel (latest features)
- `beta` - Beta channel (preview features)

#### NVIDIA GPU Operator
- `stable` - Stable channel (default)
- `v24.9` - Version 24.9
- `v24.6` - Version 24.6
- `v23.9` - Version 23.9
- `v23.6` - Version 23.6
- `v23.3` - Version 23.3
- `v22.9` - Version 22.9

#### Node Feature Discovery (NFD)
- `stable` - Stable channel (default)
- `4.17` - Version 4.17
- `4.16` - Version 4.16
- `4.15` - Version 4.15

#### OpenShift Pipelines
- `latest` - Latest stable version (default)
- `stable` - Stable channel
- `pipelines-1.15` - Pipelines 1.15
- `pipelines-1.14` - Pipelines 1.14
- `pipelines-1.13` - Pipelines 1.13

#### OpenShift Serverless
- `stable` - Stable channel (default)
- `1.34` - Serverless 1.34
- `1.33` - Serverless 1.33
- `1.32` - Serverless 1.32

#### OpenShift Service Mesh
- `stable` - Stable channel (default)
- `2.6` - Service Mesh 2.6
- `2.5` - Service Mesh 2.5
- `2.4` - Service Mesh 2.4

### GPU Instance Types

When GPU support is enabled, you can select from various AWS instance types:

#### T4 GPUs (Cost-effective)
- `g4dn.xlarge` - 1 GPU, 4 vCPUs, 16GB RAM
- `g4dn.2xlarge` - 1 GPU, 8 vCPUs, 32GB RAM
- `g4dn.4xlarge` - 1 GPU, 16 vCPUs, 64GB RAM (default)
- `g4dn.8xlarge` - 1 GPU, 32 vCPUs, 128GB RAM
- `g4dn.12xlarge` - 4 GPUs, 48 vCPUs, 192GB RAM

#### A10G GPUs (Performance)
- `g5.xlarge` - 1 GPU, 4 vCPUs, 16GB RAM
- `g5.2xlarge` - 1 GPU, 8 vCPUs, 32GB RAM
- `g5.4xlarge` - 1 GPU, 16 vCPUs, 64GB RAM
- `g5.12xlarge` - 4 GPUs, 48 vCPUs, 192GB RAM
- `g5.48xlarge` - 8 GPUs, 192 vCPUs, 768GB RAM

#### V100 GPUs (ML-optimized)
- `p3.2xlarge` - 1 GPU, 8 vCPUs, 61GB RAM
- `p3.8xlarge` - 4 GPUs, 32 vCPUs, 244GB RAM

#### A100 GPUs (High-performance)
- `p4d.24xlarge` - 8 GPUs, 96 vCPUs, 1152GB RAM (MIG-capable)

#### H100 GPUs (Cutting-edge)
- `p5.48xlarge` - 8 GPUs, 192 vCPUs, 2048GB RAM (MIG-capable)

### Custom Pod Sizes

When `--custom-notebook-sizes` or `--custom-model-sizes` is enabled, the following sizes are configured:

#### Notebook Sizes
- **Small**: 1 CPU, 8GB RAM
- **Medium**: 3 CPUs, 24GB RAM (default)
- **Large**: 7 CPUs, 56GB RAM
- **X Large**: 15 CPUs, 120GB RAM
- **XX Large**: 31 CPUs, 248GB RAM

#### Model Server Sizes
- **Small**: 1 CPU, 4GB RAM (default)
- **Medium**: 4 CPUs, 8GB RAM
- **Large**: 6 CPUs, 16GB RAM
- **X Large**: 12 CPUs, 32GB RAM

## Configuration Files

The dynamic configuration system uses two main configuration files:

### 1. Operator Versions Configuration
Location: `scripts/config/operator-versions.yaml`

This file defines available versions for each operator. You can modify this file to add new versions or change defaults.

### 2. Instance Types Configuration
Location: `scripts/config/instance-types.yaml`

This file defines GPU instance types, notebook sizes, and model server sizes. You can customize resource allocations by editing this file.

## Generated Files

When using dynamic configuration, the following files and directories are created:

1. `bootstrap/overlays/dynamic/` - Dynamic bootstrap overlay
2. `clusters/overlays/dynamic/` - Dynamic cluster configuration
3. `clusters/overlays/dynamic/patch-operators-list.yaml` - Operator version patches

## Troubleshooting

### Common Issues

1. **Missing operator version overlay**
   - Error: "kustomization.yaml not found"
   - Solution: Ensure the operator version exists in the components directory

2. **GPU nodes not starting**
   - Check AWS quotas for the selected instance type
   - Verify the instance type is available in your region

3. **Operator installation failures**
   - Check operator compatibility with your OpenShift version
   - Verify channel names match the operator's available channels

### Verification Commands

```bash
# Check created overlays
ls -la bootstrap/overlays/dynamic/
ls -la clusters/overlays/dynamic/

# Verify kustomization output
kustomize build bootstrap/overlays/dynamic/

# Check operator versions after deployment
oc get csv -A | grep -E '(gitops|openshift-ai|gpu|nfd|pipelines|serverless|servicemesh)'
```

## Best Practices

1. **Version Selection**
   - Use stable versions for production deployments
   - Test beta/fast channels in non-production environments first

2. **GPU Configuration**
   - Start with fewer GPU nodes and scale up as needed
   - Consider cost implications of different GPU instance types

3. **Resource Sizing**
   - Monitor actual resource usage and adjust sizes accordingly
   - Use custom sizes only when default sizes don't meet requirements

4. **Automation**
   - Store your configuration as a script for reproducible deployments
   - Document chosen versions and configurations for your team

## Example Deployment Scenarios

### Development Environment
```bash
./bootstrap.sh --non-interactive --dynamic \
  --ai-version=fast \
  --enable-gpu \
  --gpu-instance=g4dn.xlarge \
  --gpu-replicas=1
```

### Production Environment
```bash
./bootstrap.sh --non-interactive --dynamic \
  --gitops-version=gitops-1.13 \
  --ai-version=eus-2.16 \
  --gpu-operator-version=v24.9 \
  --enable-gpu \
  --gpu-instance=g5.4xlarge \
  --gpu-replicas=3 \
  --custom-notebook-sizes \
  --custom-model-sizes
```

### High-Performance ML Environment
```bash
./bootstrap.sh --non-interactive --dynamic \
  --ai-version=stable-2.16 \
  --gpu-operator-version=v24.9 \
  --enable-gpu \
  --gpu-instance=p4d.24xlarge \
  --gpu-replicas=2 \
  --custom-notebook-sizes \
  --custom-model-sizes
```

## Contributing

To add new operator versions or instance types:

1. Edit `scripts/config/operator-versions.yaml` for new operator versions
2. Edit `scripts/config/instance-types.yaml` for new instance types
3. Create corresponding overlays in the components directory
4. Test the configuration thoroughly before submitting a PR
