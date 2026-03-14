# Applications

This directory contains application definitions managed by FluxCD.

## Structure

- **`base/`**: Base manifests and HelmRelease templates shared across environments.
- **`overlays/`**: Environment-specific overrides.
  - **`production/`**: Production-specific settings (e.g., node selectors, ingress hosts).
  - **`development/`**: Development-specific settings.

## Adding a New App

1. Add the base definition in `apps/base/<app-name>`.
2. Create an overlay in `apps/overlays/<env>/<app-name>`.
3. Add the overlay path to `apps/overlays/<env>/kustomization.yaml`.
