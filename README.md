# Helm Charts - Kubernetes Addons

[![CI](https://github.com/nicoleepaixao/helm-charts/actions/workflows/ci.yml/badge.svg)](https://github.com/nicoleepaixao/helm-charts/actions/workflows/ci.yml)

Helm wrapper charts for EKS addons, with production-oriented values. Each chart pins an upstream dependency (versions current as of November 2026) and overrides its values for AWS: IRSA, high availability, encrypted gp3 storage, and no credentials or public dashboards in the values files.

**20 addons, 24 charts** (Istio and Linkerd each ship as two sub-charts under an umbrella folder; `storage` holds only StorageClass manifests).

![Architecture](docs/arquitetura.en.png)

## Addons

| Area | Addon | Upstream chart | Namespace | Extra manifests |
|---|---|---|---|---|
| Autoscaling | [karpenter](karpenter/) | karpenter 1.15.1 | `karpenter` | NodePool, EC2NodeClass |
| Ingress | [ingress-alb](ingress-alb/) | aws-load-balancer-controller 3.6.2 | `kube-system` | |
| Ingress (retired upstream) | [ingress-nginx](ingress-nginx/) | ingress-nginx 4.15.1 | `ingress-nginx` | |
| Ingress | [ingress-envoy](ingress-envoy/) | gateway-helm 1.9.3 | `envoy-gateway-system` | |
| Ingress | [traefik](traefik/) | traefik 42.3.0 | `traefik` | |
| Ingress / API gateway | [kong](kong/) | kong 3.4.1 | `kong` | |
| DNS and TLS | [external-dns](external-dns/) | external-dns 1.23.0 | `external-dns` | |
| DNS and TLS | [cert-manager](cert-manager/) | cert-manager v1.21.3 | `cert-manager` | ClusterIssuer |
| Service mesh | [istio](istio/) | base 1.30.7 + istiod 1.30.7 | `istio-system` | |
| Service mesh | [linkerd](linkerd/) | linkerd-crds + linkerd-control-plane 2026.11.1 | `linkerd` | |
| Network policy | [calico](calico/) | tigera-operator v3.33.0 | `calico-system` | default-deny |
| Secrets | [vault](vault/) | vault 0.34.1 | `vault` | |
| Secrets | [secrets-csi](secrets-csi/) | secrets-store-csi-driver 1.6.1 | `kube-system` | SecretProviderClass example |
| Observability | [prometheus-stack](prometheus-stack/) | kube-prometheus-stack 92.17.1 | `monitoring` | alert rules, Alertmanager config |
| Observability | [victoria-metrics](victoria-metrics/) | victoria-metrics-k8s-stack 0.97.1 | `monitoring` | |
| Observability | [logging](logging/) | aws-for-fluent-bit 0.2.0 | `logging` | |
| Observability | [uptime-kuma](uptime-kuma/) | uptime-kuma 4.2.0 | `uptime-kuma` | |
| GitOps | [argocd](argocd/) | argo-cd 10.12.0 | `argocd` | |
| Backup | [velero](velero/) | velero 12.2.3 | `velero` | |
| Storage | [storage](storage/) | (manifests only) | | gp3 and EFS StorageClasses |

> **ingress-nginx is retired.** The Kubernetes project ended its maintenance in March 2026: no new releases and no security fixes. The chart stays for existing clusters and study; for a new cluster use [Envoy Gateway](ingress-envoy/) (Gateway API) or the [ALB controller](ingress-alb/). See the [announcement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

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

`scripts/test-charts.sh` runs on every push and pull request (see the CI badge). For each of the 24 charts it runs `helm lint` and `helm template` with the chart's `values.yaml`, and then parses every file under `*/manifests/`. In CI, every rendered manifest is also validated against the Kubernetes API schema with [kubeconform](https://github.com/yannh/kubeconform) (custom resources whose schema is not published are skipped).

These checks prove the charts render valid Kubernetes objects. They do not replace installing the addons in a test cluster before production.

```bash
./scripts/test-charts.sh
```

Charts that need input to render get it from `ci/*-values.yaml`. Today only `linkerd-control-plane` has one, with placeholder certificates that must never reach a cluster.

## Upgrading from the 2024 versions

In November 2026 every addon moved from its 2024 version to the current one (for example Karpenter 1.1 → 1.15, kube-prometheus-stack 65 → 92, Velero 7 → 12). If you installed the older versions:

- **CRDs first.** Helm does not upgrade CRDs shipped in a chart's `crds/` folder. For Karpenter and kube-prometheus-stack, apply the new CRDs before `helm upgrade` (Karpenter also publishes a `karpenter-crd` chart for this).
- **Renamed values.** Traefik moved `service.type` to `service.spec.type` and the dashboard to `api.dashboard` / `ingressRoute.dashboard`; Uptime Kuma moved `persistence` to `volume`. Old names are ignored silently.
- **Plugin versions.** Velero 1.18 needs `velero-plugin-for-aws` 1.14.x.
- **Secrets.** Grafana now reads its admin password from the `grafana-admin` Secret and Alertmanager reads the Slack webhook from the `alertmanager-slack` Secret. Create both before upgrading `prometheus-stack`.
- Read each addon's release notes before a major version jump, and upgrade one addon at a time with `--atomic`.

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

Four handouts, each with objectives, architecture, concepts explained with this repo's files, summary, quiz and resources:

| Module | English | Português |
|---|---|---|
| 1. Helm and the wrapper chart pattern | [PDF](docs/apostila-1-helm.en.pdf) | [PDF](docs/apostila-1-helm.pdf) |
| 2. Scaling, storage and inbound traffic | [PDF](docs/apostila-2-trafego.en.pdf) | [PDF](docs/apostila-2-trafego.pdf) |
| 3. Service mesh, network policy and secrets | [PDF](docs/apostila-3-malha-seguranca.en.pdf) | [PDF](docs/apostila-3-malha-seguranca.pdf) |
| 4. Observability, GitOps and backup | [PDF](docs/apostila-4-observabilidade.en.pdf) | [PDF](docs/apostila-4-observabilidade.pdf) |
