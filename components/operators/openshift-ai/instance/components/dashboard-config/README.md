# Dashboard Configuration Component

This component provides custom notebook sizes, model server sizes, and accelerator profiles for OpenShift AI v2.22+.

## Background

In OpenShift AI v2.22+, the old `OdhDashboardConfig` CRD has been removed. Dashboard configurations are now managed through:

1. **Notebook Sizes**: Configured via ConfigMap that the dashboard reads
2. **Model Server Sizes**: Configured via ConfigMap that the dashboard reads  
3. **Accelerator Profiles**: Now handled differently (no longer a CRD)

## Configuration Methods

### For Notebook and Model Server Sizes

These are now configured through ConfigMaps that are mounted into the dashboard pod. The dashboard looks for specific ConfigMaps in the `redhat-ods-applications` namespace.

### For Accelerator Profiles

GPU accelerator profiles are now automatically detected based on node labels and GPU operator configuration. Manual accelerator profile creation is no longer needed in most cases.

## Usage

To use custom sizes, create ConfigMaps in the appropriate format. The dashboard will pick them up automatically.

Note: This component is a placeholder for future implementation once the exact ConfigMap format for v2.22+ is documented.
