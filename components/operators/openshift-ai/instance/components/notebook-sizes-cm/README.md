# Notebook Sizes ConfigMap Component

This component creates a ConfigMap with custom notebook sizes for OpenShift AI v2.22+.

## How it works

In OpenShift AI v2.22+, the dashboard looks for ConfigMaps with the label `opendatahub.io/dashboard: "true"` in the `redhat-ods-applications` namespace. These ConfigMaps can contain custom notebook sizes that will be available in the dashboard.

## Configuration

The `notebook-sizes-config.yaml` file contains a JSON array of notebook size definitions. Each size includes:
- `name`: Display name for the size
- `resources`: Kubernetes resource requirements
  - `limits`: Maximum CPU and memory
  - `requests`: Requested CPU and memory

## Usage

Add this component to your kustomization:

```yaml
components:
  - ../../components/notebook-sizes-cm
```

The sizes will automatically appear in the OpenShift AI dashboard when creating notebooks.
