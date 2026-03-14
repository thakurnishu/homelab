# Clusters

This directory contains the entry points for FluxCD to manage specific clusters.

## Structure

- **`flux-system/`**: Contains the core Flux components (Source Controller, Kustomize Controller, etc.).
- **`production/`**: Configuration for the production cluster.
- **`development/`**: Configuration for the development cluster (currently inactive).

## Bootstrapping a New Cluster

To bootstrap a cluster using this repository, run:

```bash
flux bootstrap git \
  --url=ssh://git@github.com/thakurnishu/homelab \
  --branch=main \
  --path=./clusters/<cluster-name>
```
