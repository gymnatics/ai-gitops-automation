# GPU Settings Component

This component configures GPU support for OpenShift AI v2.22+.

## How it works

In OpenShift AI v2.22+, GPU support is configured through:
1. The GPU operator (which must be installed separately)
2. ConfigMaps that tell the dashboard about GPU availability
3. Tolerations for GPU workloads

This component creates the necessary ConfigMaps to enable GPU support in the dashboard.

## Features

- Sets up GPU migration status to enable GPU features
- Configures default tolerations for GPU workloads
- Works with NVIDIA GPUs via the GPU operator

## Usage

Add this component to your kustomization:

```yaml
components:
  - ../../components/gpu-settings
```

Note: This component assumes you have already installed the NVIDIA GPU operator.
