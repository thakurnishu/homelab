# 🏠 Homelab

[![Kubernetes](https://img.shields.io/badge/kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Docker](https://img.shields.io/badge/docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://www.linux.org/)

Welcome to my homelab repository! This documents my personal homelab infrastructure, configurations, and services.

## 📋 Introduction

This homelab serves as my personal learning environment and self-hosted services. Built around a single-node Kubernetes cluster, it provides a flexible and scalable environment for running various applications while maintaining simplicity and efficiency.

## 🖥️ Hardware

### Single-Node Cluster

| Component      | Specification |
|---------------|---------------|
| **Machine**   | Dell Optiplex 7th Gen Mini PC |
| **CPU**       | i5-7500T (4 Cores) |
| **RAM**       | 16 GB |
| **Storage**   | 256 GB SSD |
| **OS**        | Ubuntu 24.04 |

## 🚀 Stack

### Core Infrastructure

| Component | Technology |
|-----------|------------|
| **Kubernetes** | v1.31.0 |
| **Container Runtime** | containerd |
| **CNI** | Calico |
| **Gateway** | Traefik |
| **Storage** | Longhorn |

### Monitoring & Observability

- [Prometheus](https://prometheus.io/) - Monitoring & alerting
- [Grafana](https://grafana.com/) - Metrics visualization
- [Loki](https://grafana.com/oss/loki/) - Log aggregation

### CI/CD & GitOps

- [FluxCD](https://fluxcd.io/) - GitOps tool for Kubernetes

## 🛠️ Services

### Networking

- [Cloudflare Tunnels](https://www.cloudflare.com/products/tunnel/) - Secure access to services
- [Pi-hole](https://pi-hole.net/) - Network-wide ad-blocking
- [Traefik](https://traefik.io/) - Reverse proxy and ingress controller

## 🏗️ Getting Started

### Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes command-line tool
- [Helm](https://helm.sh/) - Kubernetes package manager
- [flux](https://fluxcd.io/) - GitOps tool
- [sops](https://github.com/mozilla/sops) - Secrets management

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/homelab.git
   cd homelab
   ```

2. Install Flux:
   ```bash
   flux install
   ```

3. Apply your configurations:
   ```bash
   kubectl apply -f ./clusters/production
   ```

## 📚 Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Flux Documentation](https://fluxcd.io/docs/)
