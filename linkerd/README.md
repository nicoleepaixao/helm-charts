# linkerd

Linkerd Service Mesh — a lightweight, Rust-based service mesh that provides automatic mTLS, observability, and reliability features with minimal resource overhead and operational complexity.

## Description

Linkerd is a CNCF graduated service mesh focused on simplicity and performance. Unlike Istio's Envoy-based sidecars, Linkerd uses `linkerd2-proxy`, a purpose-built micro-proxy written in Rust. This results in significantly lower memory usage (~20MB vs ~50MB per sidecar) and lower latency overhead.

Key features:
- **Automatic mTLS** — zero-config mutual TLS between all meshed services
- **Observability** — golden metrics (success rate, latency, throughput) per service, route-level metrics, Grafana dashboards
- **Reliability** — retries, timeouts, load balancing (EWMA), circuit breaking
- **Traffic splitting** — canary deployments via `TrafficSplit` or Gateway API `HTTPRoute`
- **Authorization policies** — `Server` and `ServerAuthorization` CRDs for L4/L7 access control
- **Multi-cluster** — service mirroring across clusters

## When to Use

- You need **mTLS between services** without the operational complexity of Istio
- You want **observability** (golden metrics, success rates) without instrumenting every service
- You're on **resource-constrained clusters** where Istio's overhead is too high
- You want a **simpler operational model** — Linkerd has fewer CRDs and a gentler learning curve
- You need **reliability features** (retries, timeouts, circuit breaking) at the mesh level

## When NOT to Use

- You need **advanced traffic management** (fault injection, traffic mirroring, complex routing) — use Istio
- You need **Envoy-specific features** or Envoy filters — Linkerd uses its own proxy
- You only need **network policies** — use Calico instead (no mesh overhead)

## Comparison with Istio

| Feature | Linkerd | Istio |
|---|---|---|
| **Proxy** | linkerd2-proxy (Rust) | Envoy (C++) |
| **Memory per sidecar** | ~20MB | ~50MB |
| **Latency overhead** | <1ms p99 | ~3-5ms p99 |
| **mTLS** | ✅ Automatic | ✅ Automatic |
| **Traffic splitting** | ✅ TrafficSplit / HTTPRoute | ✅ VirtualService |
| **Fault injection** | ❌ No | ✅ Yes |
| **Traffic mirroring** | ❌ No | ✅ Yes |
| **L7 auth policies** | ✅ Server/ServerAuthorization | ✅ AuthorizationPolicy |
| **Observability** | ✅ Golden metrics, Grafana | ✅ Kiali, Jaeger, Grafana |
| **Distributed tracing** | ❌ Propagates headers only | ✅ Full (Jaeger/Zipkin) |
| **CRD count** | ~10 | ~50+ |
| **Learning curve** | Moderate | Steep |
| **Best for** | Simplicity, low overhead | Advanced traffic mgmt |

**Choose Linkerd when** you want mTLS and observability with minimal overhead and complexity. **Choose Istio when** you need advanced traffic management, fault injection, or deep Envoy customization.

## Architecture

This chart contains two sub-charts that must be installed separately and in order:

```
linkerd/
├── Chart.yaml              # This file (no dependencies — sub-charts are standalone)
├── README.md               # This file
├── linkerd-crds/           # CRDs
│   └── Chart.yaml          # Depends on linkerd-crds from Linkerd's Helm repo
└── linkerd-control-plane/  # Control plane
    ├── Chart.yaml          # Depends on linkerd-control-plane from Linkerd's Helm repo
    └── values.yaml         # Production values (trust anchor cert required)
```

> **Important:** Do NOT add sub-charts as dependencies in the parent `Chart.yaml`. They must be installed as separate Helm releases because `linkerd-crds` installs CRDs that the control plane depends on.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- `step` CLI for generating trust anchor certificates — see [Linkerd docs](https://linkerd.io/2/tasks/generate-certificates/)

### Generate Trust Anchor Certificate

```bash
step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --no-password --insecure

step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --not-after 8760h --no-password --insecure \
  --ca ca.crt --ca-key ca.key
```

Paste the contents of `ca.crt` into `linkerd-control-plane/values.yaml` under `identityTrustAnchorsPEM`.

## Install

### Step 1: Install Linkerd CRDs

```bash
cd linkerd-crds
helm dependency build
helm install linkerd-crds . -n linkerd --create-namespace
```

### Step 2: Install Linkerd Control Plane

```bash
cd ../linkerd-control-plane
# Edit values.yaml — paste your trust anchor certificate
helm dependency build
helm install linkerd-control-plane . -n linkerd \
  --set-file linkerd-control-plane.identity.issuer.tls.crtPEM=issuer.crt \
  --set-file linkerd-control-plane.identity.issuer.tls.keyPEM=issuer.key
```

### Step 3: Enable Sidecar Injection

```bash
kubectl annotate namespace default linkerd.io/inject=enabled
kubectl rollout restart deployment -n default
```

## Verify

```bash
# Check control plane
kubectl get pods -n linkerd

# Check sidecar injection (pods should show 2/2 containers)
kubectl get pods -n default

# Linkerd CLI check (if installed)
linkerd check
```

## Configure

### Traffic Splitting (Canary)

```yaml
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: my-app
spec:
  service: my-app
  backends:
    - service: my-app-stable
      weight: 900
    - service: my-app-canary
      weight: 100
```

### Authorization Policy

```yaml
apiVersion: policy.linkerd.io/v1beta3
kind: Server
metadata:
  name: my-app-http
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: my-app
  port: http
---
apiVersion: policy.linkerd.io/v1beta3
kind: ServerAuthorization
metadata:
  name: allow-frontend
  namespace: default
spec:
  server:
    name: my-app-http
  client:
    meshTLS:
      serviceAccounts:
        - name: frontend
```

## Upgrade

```bash
# Upgrade CRDs first, then control plane
cd linkerd-crds && helm dependency update && helm upgrade linkerd-crds . -n linkerd
cd ../linkerd-control-plane && helm dependency update && helm upgrade linkerd-control-plane . -n linkerd
```

## Uninstall

```bash
helm uninstall linkerd-control-plane -n linkerd
helm uninstall linkerd-crds -n linkerd
kubectl delete namespace linkerd
```

> **Warning:** Remove the `linkerd.io/inject` annotation from namespaces and restart pods before uninstalling.

## Troubleshooting

| Problem | Action |
|---|---|
| Pods stuck in Init | Check control plane: `kubectl logs -n linkerd -l linkerd.io/control-plane-component=destination` |
| mTLS not working | Verify trust anchor cert is correct: `linkerd check --proxy` |
| Certificate expired | Rotate issuer cert — see [Linkerd cert rotation docs](https://linkerd.io/2/tasks/automatically-rotating-control-plane-tls-credentials/) |
| High latency | Check proxy resource limits and `linkerd stat` output |
| Sidecar not injected | Verify namespace annotation: `kubectl get ns default -o yaml | grep linkerd` |

## Useful Commands

```bash
# Golden metrics for a deployment
linkerd stat deploy -n default

# Top requests in real-time
linkerd top deploy/my-app -n default

# Check proxy status for all meshed pods
linkerd check --proxy

# List all Linkerd CRDs
kubectl get servers,serverauthorizations,trafficsplits -A

# Control plane logs
kubectl logs -n linkerd -l linkerd.io/control-plane-component=destination

# Proxy logs for a pod
kubectl logs -n default deploy/my-app -c linkerd-proxy
```
