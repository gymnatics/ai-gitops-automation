# RHODS Admins Group Component

This component creates the `rhods-admins` group and adds the `kube:admin` user to it. This ensures that the kubeadmin user has full access to all OpenShift AI features in the dashboard.

**Note**: The `kube:admin` username is prefixed with `b64:` to comply with OpenShift's requirement that usernames containing colons must begin with this prefix.

## Usage

Add this component to your kustomization alongside the `make-kubeadmin-cluster-admin` component:

```yaml
components:
  - ../../components/make-kubeadmin-cluster-admin
  - ../../components/rhods-admins-group
```

This is typically used in development or demo environments where the kubeadmin user needs full access to OpenShift AI features.
