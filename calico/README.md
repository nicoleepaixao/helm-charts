# Calico

Calico network policies — pod-to-pod firewall rules. Uses AWS VPC CNI for networking, Calico only for policy enforcement via the Tigera operator.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- AWS VPC CNI installed (default on EKS)

## Install

```bash
helm dependency build
helm install calico . -n calico-system --create-namespace
```

Apply the default-deny policy:

```bash
kubectl apply -f manifests/default-deny.yaml
```

## Verify

```bash
kubectl get pods -n calico-system
kubectl get installation default -o yaml
kubectl get networkpolicies -A
```

All Tigera operator and Calico pods should be `Running`.

## Upgrade

```bash
helm dependency update
helm upgrade calico . -n calico-system
```

## Uninstall

Remove policies first, then the release:

```bash
kubectl delete networkpolicies --all -A
helm uninstall calico -n calico-system
```

> **Note:** CRDs are not removed by `helm uninstall`. To fully clean up:
> ```bash
> kubectl delete crd -l operator.tigera.io/managed-by=operator
> ```

## Troubleshooting

| Problem | Action |
|---|---|
| Pods can't communicate | Check networkpolicy rules: `kubectl describe networkpolicy -n <namespace>` |
| Calico pods CrashLoopBackOff | Verify `installation.cni.type` is set to `AmazonVPC` in values.yaml |
| Policy not taking effect | Ensure Calico pods are running: `kubectl get pods -n calico-system` |
| DNS resolution broken | Check that you have a NetworkPolicy allowing egress to `kube-dns` on port 53 |

## Useful Commands

```bash
# List all network policies
kubectl get networkpolicies -A

# Describe a specific policy
kubectl describe networkpolicy <name> -n <namespace>

# Test connectivity from a pod
kubectl exec -it <pod> -- curl <service>

# Check Calico operator logs
kubectl logs -n tigera-operator -l name=tigera-operator

# Check Calico node logs
kubectl logs -n calico-system -l k8s-app=calico-node
```
