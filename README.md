# Helm Charts - Kubernetes Addons

Production-ready Helm wrapper charts for EKS addons. Each chart uses an upstream dependency and overrides values for AWS/production use.

## Prerequisites

- Helm 3.x
- kubectl configured for your EKS cluster
- AWS IAM roles created for IRSA (Karpenter, cert-manager, external-dns, ALB controller)

## Install Instructions

Before installing any chart, update the placeholder values in `values.yaml` (search for `CLUSTER_NAME`, `ACCOUNT_ID`, `ROLE_NAME`, etc.).

### 1. Karpenter

```bash
cd karpenter
helm dependency build
helm install karpenter . -n kube-system --create-namespace -f values.yaml

# After Karpenter is running, apply the node manifests:
kubectl apply -f manifests/default-nodepool.yaml
kubectl apply -f manifests/ec2nodeclass.yaml
```

### 2. Ingress NGINX

```bash
cd ingress-nginx
helm dependency build
helm install ingress-nginx . -n ingress-nginx --create-namespace -f values.yaml
```

### 3. Ingress Envoy Gateway

```bash
cd ingress-envoy
helm dependency build
helm install ingress-envoy . -n envoy-gateway-system --create-namespace -f values.yaml
```

### 4. Ingress ALB (AWS Load Balancer Controller)

```bash
cd ingress-alb
helm dependency build
helm install ingress-alb . -n kube-system -f values.yaml
```

### 5. ExternalDNS

```bash
cd external-dns
helm dependency build
helm install external-dns . -n external-dns --create-namespace -f values.yaml
```

### 6. cert-manager

```bash
cd cert-manager
helm dependency build
helm install cert-manager . -n cert-manager --create-namespace -f values.yaml

# After cert-manager is running, apply the ClusterIssuer:
kubectl apply -f manifests/cluster-issuer.yaml
```

### 7. Vault (HashiCorp)

```bash
cd vault
helm dependency build
helm install vault . -n vault --create-namespace -f values.yaml
```

### 8. Uptime Kuma

```bash
cd uptime-kuma
helm dependency build
helm install uptime-kuma . -n uptime-kuma --create-namespace -f values.yaml
```

## ArgoCD (GitOps)

Each chart directory can be pointed to as an ArgoCD Application source. Example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ingress-nginx
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <YOUR_REPO_URL>
    targetRevision: main
    path: ingress-nginx
  destination:
    server: https://kubernetes.default.svc
    namespace: ingress-nginx
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

For charts with extra manifests (karpenter, cert-manager), use a multi-source Application or apply the manifests directory separately.

## References

- [Helm Documentation](https://helm.sh/docs/)
- [ArtifactHub](https://artifacthub.io/)
- [Karpenter Helm Chart](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
- [Prometheus Community Charts](https://github.com/prometheus-community/helm-charts)
- [Istio Installation with Helm](https://istio.io/latest/docs/setup/install/helm/)
- [Calico Helm Install](https://docs.tigera.io/calico/latest/getting-started/kubernetes/helm)

## Study notes

Handouts with objectives, architecture, concepts using this repo's code, summary, quiz and resources: [English](docs/apostila.en.pdf) · [Português](docs/apostila.pdf)
