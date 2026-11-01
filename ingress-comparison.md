# Ingress Controllers Comparison

Comprehensive comparison of all ingress controllers available in this repository for EKS clusters.

## Comparison Table

| Feature | Nginx | Kong | Traefik | Envoy Gateway | ALB Controller | API Gateway |
|---|---|---|---|---|---|---|
| **Type** | L7 Reverse Proxy | API Gateway + L7 Proxy | L7 Reverse Proxy | L7/L4 Proxy (Gateway API) | AWS-native L7 LB | AWS-native API GW |
| **Protocol Support** | HTTP/HTTPS, TCP/UDP, gRPC, WebSocket | HTTP/HTTPS, TCP/UDP, gRPC, WebSocket | HTTP/HTTPS, TCP/UDP, gRPC, WebSocket | HTTP/HTTPS, TCP/UDP, gRPC, WebSocket | HTTP/HTTPS, gRPC, WebSocket | HTTP/HTTPS, WebSocket, REST, HTTP API |
| **Rate Limiting** | ❌ Basic (nginx annotations) | ✅ Advanced (per consumer/route/global) | ✅ Middleware (per route) | ✅ Via BackendTrafficPolicy | ❌ No | ✅ Per API key/stage |
| **Auth Plugins** | ❌ External auth only | ✅ JWT, OAuth2, Key-Auth, LDAP, HMAC | ✅ BasicAuth, ForwardAuth, DigestAuth | ✅ JWT, OIDC, ExtAuth | ✅ Cognito, OIDC | ✅ Cognito, Lambda authorizer, IAM |
| **Auto-discovery** | ❌ Manual Ingress resources | ❌ Manual Ingress/CRDs | ✅ Automatic | ❌ Manual Gateway API resources | N/A (annotation-based) | N/A (AWS-managed) |
| **Dashboard** | ❌ No built-in | ✅ Kong Manager (Enterprise) | ✅ Built-in (free) | ❌ No built-in | AWS Console | AWS Console |
| **WAF Support** | ❌ ModSecurity (complex) | ✅ Bot detection, IP restriction | ✅ IP whitelist, headers | ❌ Not built-in | ✅ AWS WAF integration | ✅ AWS WAF integration |
| **mTLS** | ✅ Via annotations | ✅ Native | ✅ Native | ✅ Native (Gateway API) | ❌ No | ✅ Client certificates |
| **WebSocket** | ✅ Native | ✅ Native | ✅ Native | ✅ Native | ✅ Native | ✅ Native |
| **gRPC** | ✅ Native | ✅ Native | ✅ Native | ✅ Native | ✅ Native | ✅ Via HTTP/2 |
| **TLS Termination** | ✅ In-cluster | ✅ In-cluster | ✅ In-cluster + ACME | ✅ In-cluster | ✅ ACM (AWS-managed) | ✅ ACM (AWS-managed) |
| **Cost** | Free (NLB cost only) | Free OSS / Enterprise paid | Free (NLB cost only) | Free (NLB cost only) | Free (ALB cost only) | Pay per request + data |
| **In-cluster Component** | ✅ Yes (pods) | ✅ Yes (pods) | ✅ Yes (pods) | ✅ Yes (pods) | ✅ Yes (controller pods) | ❌ No (fully managed) |
| **Complexity** | Low | Medium-High | Low-Medium | Medium | Low | Low-Medium |
| **Config Model** | Ingress annotations | CRDs (KongPlugin, KongConsumer) | Ingress + IngressRoute CRD | Gateway API resources | Ingress annotations | AWS API/Console/IaC |
| **Best for** | Simple routing, most common | API-heavy, need plugins at ingress | Dynamic envs, auto-discovery | Gateway API standard, future-proof | AWS-native, WAF, zero config | Serverless, Lambda, fully managed |

## Detailed Analysis

### Nginx Ingress Controller
The most widely adopted ingress controller. Battle-tested, simple to configure, and well-documented. Uses standard Kubernetes Ingress resources with annotations for customization. Best choice when you need straightforward HTTP routing without advanced features.

### Kong Ingress Controller
A full API Gateway running as an ingress controller. Unique strength: per-consumer rate limiting, key authentication, request/response transformations, and 100+ plugins — all configured via CRDs. Heavier than Nginx/Traefik but provides API management features that would otherwise require a separate component.

### Traefik
Designed for dynamic environments. Automatically discovers services and creates routes. Supports both standard Ingress and its own IngressRoute CRD. Built-in dashboard provides real-time visibility. Middleware system handles rate limiting, auth, circuit breaking, and retries without external tools.

### Envoy Gateway
The Kubernetes Gateway API reference implementation built on Envoy proxy. Uses the new Gateway API standard (`Gateway`, `HTTPRoute`, `GRPCRoute`) instead of the legacy Ingress resource. Best for teams that want to adopt the Gateway API standard, which will eventually replace Ingress.

### ALB Controller
Provisions AWS Application Load Balancers for each Ingress resource. No in-cluster proxy — traffic goes directly from ALB to pods. Native AWS WAF integration, ACM for TLS, and Cognito for auth. Best when you want AWS-managed infrastructure with minimal in-cluster components.

### API Gateway (Amazon)
Fully managed, serverless API gateway. No in-cluster components at all. Best for Lambda-backed APIs or when you want per-request pricing. Supports REST APIs, HTTP APIs, and WebSocket APIs. Not a traditional ingress controller — more suited for API-first architectures with AWS-native backends.

## Decision Flowchart

```
Start: Which ingress controller should I use?
│
├─ Do you need API management features (rate limiting per consumer, auth plugins, transformations)?
│  ├─ YES → Kong
│  └─ NO ↓
│
├─ Do you want auto-discovery and a built-in dashboard?
│  ├─ YES → Traefik
│  └─ NO ↓
│
├─ Do you want to adopt the Gateway API standard (future of K8s ingress)?
│  ├─ YES → Envoy Gateway
│  └─ NO ↓
│
├─ Do you want AWS-managed load balancing with WAF integration?
│  ├─ YES → Is your backend serverless (Lambda)?
│  │  ├─ YES → API Gateway
│  │  └─ NO → ALB Controller
│  └─ NO ↓
│
├─ Do you just need simple, reliable HTTP routing?
│  └─ YES → Nginx (most common, battle-tested)
│
└─ Still unsure?
   └─ Start with Nginx. Migrate later if you outgrow it.
```

## Running Multiple Ingress Controllers

You can run multiple ingress controllers simultaneously. Each Ingress resource specifies which controller handles it via `ingressClassName`:

```yaml
# Handled by Nginx
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-app
spec:
  ingressClassName: nginx
  ...

# Handled by Kong
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
spec:
  ingressClassName: kong
  ...

# Handled by Traefik
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: internal-app
spec:
  ingressClassName: traefik
  ...
```

Common pattern: **Nginx for web apps** + **Kong for APIs** — each gets its own NLB and can be configured independently.

## Cost Comparison (EKS on AWS)

| Component | Nginx | Kong | Traefik | Envoy | ALB | API Gateway |
|---|---|---|---|---|---|---|
| Controller pods | ~256Mi RAM | ~512Mi RAM | ~256Mi RAM | ~256Mi RAM | ~128Mi RAM | None |
| Load Balancer | NLB (~$16/mo) | NLB (~$16/mo) | NLB (~$16/mo) | NLB (~$16/mo) | ALB (~$22/mo) | Pay per request |
| Data processing | NLB rates | NLB rates | NLB rates | NLB rates | ALB rates | $1/million requests |
| License | Free (OSS) | Free (OSS) / Enterprise | Free (OSS) | Free (OSS) | Free | Pay-as-you-go |

> **Note:** NLB pricing is ~$0.0225/hr + data processing. ALB pricing is ~$0.0225/hr + LCU charges. API Gateway is $1.00-$3.50 per million requests depending on type. All prices are approximate and region-dependent — check [AWS Pricing](https://aws.amazon.com/pricing/) for current rates.

## Current Cluster Status

The `eks-teste` cluster is currently running **ingress-nginx**. Kong and Traefik are available as additional options and can be deployed alongside Nginx using different `ingressClassName` values.
