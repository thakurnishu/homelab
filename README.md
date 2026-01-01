# 🏠 Kubernetes Homelab

[![Kubernetes](https://img.shields.io/badge/kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Flux](https://img.shields.io/badge/flux-2962FF?style=for-the-badge&logo=flux&logoColor=white)](https://fluxcd.io/)

This repository contains the **Infrastructure as Code (IaC)** and **GitOps configurations** for my personal homelab. It is built around a single-node Kubernetes cluster and uses **FluxCD** to automatically reconcile the cluster state with this repository.

## 🏗️ Architecture

The cluster is managed declaratively using GitOps principles.

- **GitOps Engine**: [FluxCD](https://fluxcd.io/)
- **Secret Management**: [SOPS](https://github.com/mozilla/sops) with Age encryption
- **Ingress Controller**: [Traefik](https://traefik.io/) and [Istio](https://istio.io/)
- **Policy Enforcement**: [Kyverno](https://kyverno.io/)

## 📂 Repository Structure

The repository follows a standard FluxCD structure, separating infrastructure from applications.

### 1. `clusters/`
The entry point for FluxCD.
- **`development/`**: The main cluster configuration.
    - Defines the `GitRepository` source.
    - Bootstraps the `Kustomization` resources for `apps` and `infrastructure`.
    - Configures SOPS decryption.

### 2. `infrastructure/`
Core platform services and controllers that keep the cluster running.
- **`controllers/`**: Helm releases for system components.
    - **Networking**: `traefik` (Ingress), `metallb` (Load Balancer), `cloudflared` (Tunnels), `pihole` (DNS/Ad-blocking).
    - **Storage**: `longhorn` (Distributed Block Storage), `cloudnativepg` (Postgres Operator).
    - **Observability**: `monitoring` (Prometheus/Grafana), `signoz` (APM), `loki` (Logs), `opentelemetry-collector`.
    - **Security**: `cert-manager` (TLS), `kyverno` (Policies), `actions-runner-controller` (GitHub Actions).
- **`configs/`**: Configuration resources for the controllers (e.g., `ClusterIssuer`, `IPAddressPool`).

### 3. `apps/`
User-facing applications and workloads, organized using **Kustomize** (`base` and `overlays`).
- **`minimaldo`**: Custom todo/task application.
- **`n8n`**: Workflow automation platform.
- **`sonarqube`**: Code quality and security inspection.
- **`owasp-dependency-track`**: Software Bill of Materials (SBOM) analysis.
- **`signoz`**: Application performance monitoring frontend.
- **`secrets`**: Encrypted secrets managed via SOPS.

### 4. `homelab-setup/`
Scripts and configurations for bootstrapping the physical nodes or VMs.
- **`kubeadm`** / **`talos`**: Bootstrapping configurations.
- **`k8s.sh`**: Initial node setup script.
- **`proxmox`**: Virtualization helper scripts.

### 5. `scripts/`
Maintenance and utility scripts.
- **`sops-encrypt-all.sh`**: Automates the encryption of secrets matching `.sops.yaml` rules.
- **`ns-delete.sh`**: Helper to force delete stuck namespaces.

## 🔄 Workflow

1.  **Develop**: Make changes to Kubernetes manifests in `apps/` or `infrastructure/`.
2.  **Encrypt**: If adding secrets, create a `.secret.yaml` file and run `./scripts/sops-encrypt-all.sh`.
3.  **Commit**: Push changes to the `main` branch.
4.  **Deploy**: FluxCD detects the commit, decrypts secrets in-cluster, and applies the changes automatically.

## 🔐 Secret Management

Secrets are encrypted using **SOPS** with **Age**.
- **Public Key**: `.sops.yaml` contains the public key for encryption.
- **Private Key**: Stored securely in the cluster as a Kubernetes Secret (`sops-age`), allowing Flux to decrypt manifests at apply time.

## 🚀 Getting Started

### Prerequisites
- `kubectl`
- `flux` CLI
- `sops`
- `age`

### Bootstrap
To bootstrap the cluster (assuming a fresh node):

```bash
# 1. Clone the repo
git clone https://github.com/personal/homelab.git
cd homelab

# 2. Setup SOPS encryption for Cluster
bash homelab-setup/sops-setup.sh

# 3. Bootstrap Flux
bash homelab-setup/fluxcd-bootstrap.sh
```
