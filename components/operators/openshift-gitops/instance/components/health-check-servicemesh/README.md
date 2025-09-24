# Service Mesh Health Check Component

This component adds health check configuration for Service Mesh resources to the ArgoCD instance.

## What it does

Adds a custom health check for `ServiceMeshControlPlane` resources that properly reports:
- Healthy: When the control plane is ready
- Progressing: When components are being deployed
- Degraded: When there are errors

This ensures ArgoCD properly waits for Service Mesh to be ready before proceeding with dependent resources like OpenShift AI.
