# Infrastructure

Shared infrastructure components and configurations.

## Structure

- **`controllers/`**: K8s Operators and Controllers.
- **`configs/`**: Global configurations (SecretStores, ClusterIssuers, etc.).
- **`namespaces/`**: Namespace definitions.

## Adding a New Component

1. Create a directory for the component in `controllers/`.
2. Define the `HelmRepository` and `HelmRelease` (or other manifests).
3. Add the path to `infrastructure/controllers/kustomization.yaml`.
4. If it requires global config, add it to `configs/` and update `infrastructure/configs/kustomization.yaml`.
