# 🏠 Homelab Infrastructure Documentation

## 📋 Overview
This document provides a comprehensive overview of the homelab infrastructure, including its architecture, components, and setup instructions. The homelab is built around a single-node Kubernetes cluster, providing a flexible and scalable environment for running various applications and services.

## 🏗️ Architecture

### Core Infrastructure
- **Kubernetes**: v1.31.0 single-node cluster
- **Container Runtime**: containerd
- **CNI**: Calico for networking
- **Service Mesh**: Traefik as the ingress controller
- **Storage**: Longhorn for persistent storage
- **GitOps**: FluxCD for continuous delivery

### Hardware
| Component      | Specification |
|----------------|---------------|
| **Machine**   | Dell Optiplex 7th Gen Mini PC |
| **CPU**       | i5-7500T (4 Cores) |
| **RAM**       | 16 GB |
| **Storage**   | 256 GB SSD |
| **OS**        | Ubuntu 24.04 |

## 📁 Directory Structure

### 1. `/apps`
Contains Kubernetes application manifests organized using Kustomize.
- **`/base`**: Base configurations for applications
- **`/overlays`**: Environment-specific configurations (development, production)

### 2. `/clusters`
Kubernetes cluster configurations.
- **`/development`**: Development cluster configuration

### 3. `/homelab-setup`
Initial setup and configuration scripts.
- **`/files`**: Configuration templates and static files
- **`k8s.sh`**: Kubernetes cluster bootstrap script
- **`nginx-proxy.sh`**: Nginx reverse proxy setup
- **`pihole.sh`**: Pi-hole installation script
- **`startup.sh`**: System startup configuration

### 4. `/infrastructure`
Infrastructure as Code (IaC) configurations.
- **`/configs`**: Infrastructure configuration files
- **`/controllers`**: Custom controllers and operators

### 5. `/policies`
Security and governance policies.
- **`/kyverno`**: Kyverno policies for Kubernetes
- **`/networkpolicy`**: Network policies for cluster security

### 6. `/scripts`
Utility scripts for maintenance and operations.
- **`ns-delete.sh`**: Namespace cleanup script
- **`sops-encrypt-all.sh`**: Secrets encryption script

## 🛠️ Applications & Infrastructure Tools

This section provides a deep-dive into all applications and infrastructure tools installed in the cluster, grouped by category, with each tool’s role explained.

### 🗂️ Applications (Self-Hosted & Platform Services)
- **minimaldo** (backend & frontend): Custom or third-party application, likely for personal or workflow use.
- **n8n**: Open-source workflow automation platform for integrating services and automating tasks.
- **OWASP Dependency-Track**: Software composition analysis platform for tracking and managing vulnerabilities in dependencies.
- **Signoz**: Open-source observability platform for distributed tracing, metrics, and logs.
- **SonarQube**: Continuous inspection of code quality and security.
- **Secrets**: Secure storage for sensitive data (e.g., image pull secrets, backup credentials).

### 🏗️ Infrastructure Tools (Controllers, Operators, System Services)
- **Kubernetes**: Core container orchestration platform (v1.31.0, single-node).
- **FluxCD**: GitOps operator for automated, continuous delivery from Git.
- **SOPS**: Secrets management and encryption for Kubernetes manifests.
- **actions-runner-controller**: Manages self-hosted GitHub Actions runners on Kubernetes.
- **cert-manager**: Automated management and issuance of TLS certificates.
- **cloudnativepg**: Kubernetes operator for managing PostgreSQL clusters.
- **longhorn**: Distributed block storage for persistent volumes.
- **metallb**: Load balancer implementation for bare-metal Kubernetes clusters.
- **monitoring stack**: Includes Prometheus, Grafana, AlertManager, Loki, and Signoz for metrics, logs, and alerting.
- **cloudflared**: Secure tunneling to Cloudflare for remote access and zero-trust networking.
- **kyverno**: Kubernetes-native policy management and enforcement.
- **metrics-server**: Resource usage metrics for Kubernetes (CPU/memory).
- **opentelemetry-collector**: Observability data pipeline for collecting, processing, and exporting telemetry data.
- **traefik**: Ingress controller for HTTP routing and load balancing.

### 🔍 Summary Table

| Category            | Tool/Service                | Role in Homelab                                                                                   |
|---------------------|-----------------------------|---------------------------------------------------------------------------------------------------|
| **CI/CD**               | FluxCD, actions-runner-controller | GitOps delivery, GitHub Actions runners for automation                                      |
| **Monitoring**          | Prometheus, Grafana, Loki, AlertManager, signoz, opentelemetry-collector | Metrics, logs, alerting, tracing, observability      |
| **Security/Policy**     | Kyverno, cert-manager, SOPS, secrets | Policy enforcement, certificate management, secrets encryption                                    |
| **Networking**          | Traefik, Metallb, cloudflared | Ingress, L4/L7 load balancing, secure tunnels                                                     |
| **Storage**             | Longhorn, cloudnativepg     | Persistent storage, PostgreSQL operator                                                           |
| **Automation**          | n8n                         | Workflow automation                                                                               |
| **Code Quality**        | SonarQube, owasp-dependency-track | Code analysis, vulnerability management                                                           |
| **Custom Apps**         | minimaldo (backend/frontend) | Custom or third-party application                                                                 |
| **Utilities**           | metrics-server, scripts     | Cluster metrics, automation scripts (namespace deletion, SOPS encryption, etc.)                   |

### 🧩 How Components Interact
- **GitOps**: FluxCD manages application and infra deployments from Git.
- **Ingress & Networking**: Traefik routes traffic, Metallb provides load balancing, Cloudflared enables secure external access.
- **Monitoring**: Prometheus scrapes metrics, Grafana visualizes, AlertManager notifies, Loki and Signoz collect logs/traces.
- **Security**: Kyverno enforces policies, cert-manager issues certificates, SOPS encrypts secrets.
- **Storage**: Longhorn provides persistent volumes, cloudnativepg manages PostgreSQL clusters.
- **CI/CD**: actions-runner-controller provisions self-hosted runners for GitHub Actions workflows.
- **Automation**: n8n runs custom workflows, scripts automate cluster maintenance.

> **Note:** All applications and infrastructure tools are managed declaratively via Kubernetes manifests, with overlays for environment-specific customization. Secrets are encrypted using SOPS and managed by FluxCD.

---

## 🔄 Workflow

### GitOps with FluxCD
1. Changes are committed to the Git repository
2. FluxCD detects changes and reconciles the cluster state
3. Applications are automatically deployed/updated in the cluster

### Secrets Management
- **SOPS** is used for encrypting sensitive data
- Secrets are stored securely in Git
- Automatic decryption using FluxCD SOPS integration

## 🔄 Workflow

### GitOps with FluxCD
1. Changes are committed to the Git repository
2. FluxCD detects changes and reconciles the cluster state
3. Applications are automatically deployed/updated in the cluster

### Secrets Management
- **SOPS** is used for encrypting sensitive data
- Secrets are stored securely in Git
- Automatic decryption using FluxCD SOPS integration

## 🚀 Getting Started

### Prerequisites
- `kubectl` (v1.24+)
- `flux` CLI
- `sops` for secrets management
- `helm` (v3+)

### Initial Setup
1. Clone the repository:
   ```bash
   git clone https://github.com/thakurnishu/homelab.git
   cd homelab
   ```

2. Setup SOPS encryption for Cluster:
   ```bash
   bash homelab-setup/sops-setup.sh
   ```

3. Bootstrap Flux:
   ```bash
   bash homelab-setup/fluxcd-bootstrap.sh
   ```

## 🔒 Security

### Network Policies
- Default deny-all policy for all namespaces
- Explicit allow rules for required traffic
- Network segmentation between applications

### Access Control
- RBAC configured for all components
- Service accounts with least privilege
- Regular security audits and updates

## 📈 Monitoring & Maintenance

### Monitoring Stack
- **Prometheus**: Metrics collection for all cluster and application workloads
- **Grafana**: Visual dashboards for real-time and historical metrics
- **Loki**: Centralized log aggregation for all workloads
- **Signoz**: Distributed tracing, metrics, and logs for observability
- **AlertManager**: Notification and alerting system for incidents

### Maintenance Tasks
- Automated regular backups of critical data (see scripts and backup secrets)
- Automated certificate management (cert-manager)
- Resource usage monitoring (metrics-server, Prometheus)
- Namespace and resource cleanup scripts

---

For a complete list of manifests, overlays, and scripts, see the `/apps`, `/infrastructure`, and `/scripts` directories. Each tool or application is managed as code and can be customized or extended as needed.

If you need a more granular breakdown (e.g., every Helm chart, CRD, or manifest), or want to add more architectural diagrams or flowcharts, let me know!
