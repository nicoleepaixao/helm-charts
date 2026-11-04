# Helm Charts - Kubernetes Addons

[![CI](https://github.com/nicoleepaixao/helm-charts/actions/workflows/ci.yml/badge.svg)](https://github.com/nicoleepaixao/helm-charts/actions/workflows/ci.yml)

Production-ready Helm wrapper charts for EKS addons. Each chart pins an upstream dependency and overrides its values for AWS and production use.

**20 addons, 24 charts** (Istio and Linkerd each ship as two sub-charts under an umbrella folder; `storage` holds only StorageClass manifests).

![Architecture](docs/arquitetura.en.png)

## Addons

| Area | Addon | Upstream chart | Namespace | Extra manifests |
|---|---|---|---|---|
| Autoscaling | [karpenter](karpenter/) | karpenter 1.1.1 | `karpenter` | NodePool, EC2NodeClass |
| Ingress | [ingress-alb](ingress-alb/) | aws-load-balancer-controller 1.8.4 | `kube-system` | |
| Ingress | [ingress-nginx](ingress-nginx/) | ingress-nginx 4.11.3 | `ingress-nginx` | |
| Ingress | [ingress-envoy](ingress-envoy/) | gateway-helm 1.2.4 | `envoy-gateway-system` | |
| Ingress | [traefik](traefik/) | traefik 32.0.0 | `traefik` | |
| Ingress / API gateway | [kong](kong/) | kong 2.41.0 | `kong` | |
| DNS and TLS | [external-dns](external-dns/) | external-dns 1.15.0 | `external-dns` | |
| DNS and TLS | [cert-manager](cert-manager/) | cert-manager 1.16.2 | `cert-manager` | ClusterIssuer |
| Service mesh | [istio](istio/) | base 1.23.0 + istiod 1.23.0 | `istio-system` | |
| Service mesh | [linkerd](linkerd/) | linkerd-crds + linkerd-control-plane 2026.11.1 | `linkerd` | |
| Network policy | [calico](calico/) | tigera-operator 3.28.0 | `calico-system` | default-deny |
| Secrets | [vault](vault/) | vault 0.28.1 | `vault` | |
| Secrets | [secrets-csi](secrets-csi/) | secrets-store-csi-driver 1.4.6 | `kube-system` | SecretProviderClass example |
| Observability | [prometheus-stack](prometheus-stack/) | kube-prometheus-stack 65.1.0 | `monitoring` | alert rules, Alertmanager config |
| Observability | [victoria-metrics](victoria-metrics/) | victoria-metrics-k8s-stack 0.25.0 | `monitoring` | |
| Observability | [logging](logging/) | aws-for-fluent-bit 0.1.34 | `logging` | |
| Observability | [uptime-kuma](uptime-kuma/) | uptime-kuma 2.20.0 | `uptime-kuma` | |
| GitOps | [argocd](argocd/) | argo-cd 7.3.11 | `argocd` | |
| Backup | [velero](velero/) | velero 7.2.1 | `velero` | |
| Storage | [storage](storage/) | (manifests only) | | gp3 and EFS StorageClasses |

Each folder has its own README with what the addon does, when to use it, when not to, and the install steps. Guides that span several addons: [ingress controllers comparison](ingress-comparison.md) and [disaster recovery](disaster-recovery.md).

## Prerequisites

- Helm 3.x
- kubectl configured for your EKS cluster
- IAM roles for IRSA where the addon calls AWS (Karpenter, cert-manager, external-dns, ALB controller, Velero, Fluent Bit)

## Install

Every addon follows the same steps. Before installing, replace the placeholders in `values.yaml` (search for `CLUSTER_NAME`, `ACCOUNT_ID`, `ROLE_NAME`, `CHANGE_ME`).

```bash
cd <addon>
helm dependency build
helm install <addon> . -n <namespace> --create-namespace -f values.yaml

# only for addons with a manifests/ folder, after the chart is running:
kubectl apply -f manifests/
```

Install order that avoids most surprises: storage → karpenter → ingress-alb and external-dns → cert-manager → the rest. For Istio install `istio-base` before `istiod`; for Linkerd install `linkerd-crds` before `linkerd-control-plane`.

## Tests

`scripts/test-charts.sh` runs on every push and pull request (see the CI badge). For each of the 24 charts it runs `helm lint` and `helm template` with the chart's `values.yaml`, and then parses every file under `*/manifests/`.

```bash
./scripts/test-charts.sh
```

Charts that need input to render get it from `ci/*-values.yaml`. Today only `linkerd-control-plane` has one, with placeholder certificates that must never reach a cluster.

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

For charts with extra manifests (karpenter, cert-manager, calico, prometheus-stack, secrets-csi, storage), use a multi-source Application or apply the manifests directory separately.

## References

- [Helm Documentation](https://helm.sh/docs/)
- [ArtifactHub](https://artifacthub.io/)
- [Karpenter Helm Chart](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
- [Prometheus Community Charts](https://github.com/prometheus-community/helm-charts)
- [Istio Installation with Helm](https://istio.io/latest/docs/setup/install/helm/)
- [Calico Helm Install](https://docs.tigera.io/calico/latest/getting-started/kubernetes/helm)

## Study notes

Handouts with objectives, architecture, concepts using this repo's code, summary, quiz and resources: [English](docs/apostila.en.pdf) · [Português](docs/apostila.pdf)
