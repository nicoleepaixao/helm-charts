# istio

Istio Service Mesh — provides mutual TLS (mTLS) between all services, traffic management (canary, blue-green, fault injection), and deep observability (distributed tracing, metrics, access logs) without changing application code.

## Description

Istio is a service mesh that injects an Envoy sidecar proxy into every pod. All traffic between services flows through these proxies, enabling the mesh to enforce security policies, manage traffic, and collect telemetry transparently.

Key features:
- **mTLS everywhere** — automatic encryption and identity between all services, zero code changes
- **Traffic management** — canary deployments, blue-green, traffic mirroring, fault injection, retries, timeouts via `VirtualService` and `DestinationRule` CRDs
- **Observability** — distributed tracing (Jaeger/Zipkin), metrics (Prometheus), access logs, service graph (Kiali)
- **Authorization policies** — L7 access control (allow service A to call service B on GET /api only)
- **Rate limiting and circuit breaking** — at the mesh level without application changes

## When to Use

- You have **many services** communicating over the network and need mTLS without managing certificates per service
- You need **traffic management** (canary releases, traffic splitting, fault injection) at the infrastructure level
- You need **L7 authorization policies** between services (not just network policies)
- You need **deep observability** (distributed tracing, service graphs) across all services
- You're running a **multi-team platform** and want consistent security/observability across all workloads

## When NOT to Use

- You have **fewer than 5-10 services** — the operational overhead of Istio is not worth it for small deployments
- You only need **mTLS** — consider Linkerd instead (simpler, lighter)
- You only need **network policies** — use Calico instead
- Your team is **not ready** for the operational complexity — Istio has a steep learning curve
- **Resource-constrained clusters** — each sidecar adds ~50MB memory and ~10ms latency

## Comparison with Linkerd

| Feature | Istio | Linkerd |
|---|---|---|
| **Proxy** | Envoy (C++) | linkerd2-proxy (Rust) |
| **Resource usage** | Higher (~50MB/sidecar) | Lower (~20MB/sidecar) |
| **Complexity** | High | Low-Medium |
| **Traffic management** | ✅ Full (VirtualService, DestinationRule) | ✅ Basic (TrafficSplit, HTTPRoute) |
| **mTLS** | ✅ Automatic | ✅ Automatic |
| **Authorization policies** | ✅ L7 (method, path, headers) | ✅ L4/L7 (Server, ServerAuthorization) |
| **Multi-cluster** | ✅ Mature | ✅ Supported |
| **Observability** | ✅ Deep (Kiali, Jaeger, Grafana) | ✅ Good (built-in dashboard, Grafana) |
| **Learning curve** | Steep | Moderate |
| **Best for** | Large platforms, advanced traffic mgmt | Simpler meshes, resource efficiency |

**Choose Istio when** you need advanced traffic management (canary, fault injection, mirroring), deep L7 authorization, or Kiali service graphs. **Choose Linkerd when** you want mTLS and observability with less complexity and lower resource usage.

## Architecture

This chart contains two sub-charts that must be installed separately and in order:

```
istio/
├── Chart.yaml          # This file (no dependencies — sub-charts are standalone)
├── README.md           # This file
├── istio-base/         # CRDs and cluster-wide resources
│   └── Chart.yaml      # Depends on istio/base from Istio's Helm repo
└── istiod/             # Control plane (Pilot, CA, xDS server)
    ├── Chart.yaml      # Depends on istio/istiod from Istio's Helm repo
    └── values.yaml     # Production values
```

> **Important:** Do NOT add `istio-base` and `istiod` as dependencies in the parent `Chart.yaml`. They must be installed as separate Helm releases because `istio-base` installs CRDs that `istiod` depends on.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+

## Install

### Step 1: Install Istio Base (CRDs)

```bash
cd istio-base
helm dependency build
helm install istio-base . -n istio-system --create-namespace
```

### Step 2: Install Istiod (Control Plane)

```bash
cd ../istiod
helm dependency build
helm install istiod . -n istio-system
```

### Step 3: Enable Sidecar Injection

Label namespaces where you want automatic sidecar injection:

```bash
kubectl label namespace default istio-injection=enabled
```

Restart existing pods to inject sidecars:

```bash
kubectl rollout restart deployment -n default
```

## Verify

```bash
# Check istiod is running
kubectl get pods -n istio-system

# Check sidecar injection is working (pods should show 2/2 containers)
kubectl get pods -n default

# Verify mTLS is active
kubectl exec -n default deploy/my-app -c istio-proxy -- curl -s localhost:15000/clusters | grep "transport_socket"
```

## Configure

### Traffic Splitting (Canary)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
    - my-app
  http:
    - route:
        - destination:
            host: my-app
            subset: stable
          weight: 90
        - destination:
            host: my-app
            subset: canary
          weight: 10
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-app
spec:
  host: my-app
  subsets:
    - name: stable
      labels:
        version: v1
    - name: canary
      labels:
        version: v2
```

### Authorization Policy

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-frontend-to-api
  namespace: default
spec:
  selector:
    matchLabels:
      app: api
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/default/sa/frontend"]
      to:
        - operation:
            methods: ["GET"]
            paths: ["/api/*"]
```

## Upgrade

```bash
# Upgrade base first, then istiod
cd istio-base && helm dependency update && helm upgrade istio-base . -n istio-system
cd ../istiod && helm dependency update && helm upgrade istiod . -n istio-system
```

## Uninstall

```bash
# Remove istiod first, then base
helm uninstall istiod -n istio-system
helm uninstall istio-base -n istio-system
kubectl delete namespace istio-system
```

> **Warning:** Remove the `istio-injection` label from namespaces and restart pods before uninstalling, otherwise pods will fail to start (sidecar injection webhook will be gone but the label will still trigger it).

## Troubleshooting

| Problem | Action |
|---|---|
| Pods stuck in Init | Sidecar injection webhook failing — check istiod logs: `kubectl logs -n istio-system -l app=istiod` |
| mTLS not working | Check PeerAuthentication policy: `kubectl get peerauthentication -A` |
| VirtualService not routing | Verify DestinationRule subsets match pod labels |
| High latency after mesh | Check sidecar resource limits and Envoy access logs |
| Sidecar not injected | Verify namespace label: `kubectl get ns default --show-labels` |
| CRD errors on istiod install | Install istio-base first — CRDs must exist before istiod |

## Useful Commands

```bash
# Check mesh status
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{" "}{end}{"\n"}{end}' | grep istio-proxy

# View Envoy proxy config for a pod
kubectl exec -n default deploy/my-app -c istio-proxy -- pilot-agent request GET config_dump

# Check mTLS mode
kubectl get peerauthentication -A

# List all Istio CRDs
kubectl get virtualservices,destinationrules,gateways,authorizationpolicies -A

# Istiod logs
kubectl logs -n istio-system -l app=istiod

# Proxy access logs
kubectl logs -n default deploy/my-app -c istio-proxy
```
