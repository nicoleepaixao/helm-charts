# Karpenter

Karpenter — fast node autoscaling. Provisions optimal EC2 instances in 30–60 seconds when pods are pending, and consolidates underutilized nodes to reduce cost.

## Prerequisites

- IRSA role ARN from `terraform output karpenter_role_arn`
- SQS interruption queue from `terraform output karpenter_interruption_queue`
- Subnets tagged with `karpenter.sh/discovery: <cluster-name>`
- Security groups tagged with `karpenter.sh/discovery: <cluster-name>`

## Install

Update `values.yaml` with the role ARN, cluster name, and cluster endpoint, then:

```bash
helm dependency build
helm install karpenter . -n karpenter --create-namespace
kubectl apply -f manifests/
```

## Verify

```bash
kubectl get pods -n karpenter
kubectl get nodepools
kubectl get ec2nodeclasses
kubectl get nodeclaims
```

Test autoscaling — create a deployment that requests more CPU than available, and watch nodes appear in 30–60s:

```bash
kubectl scale deployment inflate --replicas=10
```

Clean up: `kubectl delete deployment inflate`

## Upgrade

```bash
helm dependency update
helm upgrade karpenter . -n karpenter
```

After upgrading, re-apply manifests if CRD versions changed:

```bash
kubectl apply -f manifests/
```

## Uninstall

Remove CRDs first, then the release:

```bash
kubectl delete nodeclaims --all
kubectl delete nodepools --all
kubectl delete ec2nodeclasses --all
helm uninstall karpenter -n karpenter
```

> **Warning:** Deleting NodeClaims will terminate the underlying EC2 instances. Ensure workloads can be rescheduled to other nodes.

## Troubleshooting

| Problem | Action |
|---|---|
| Nodes not provisioning | Check Karpenter logs: `kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter` |
| IRSA permission errors | Verify the ServiceAccount annotation and IAM role trust policy |
| No matching instance types | Check EC2NodeClass `subnetSelectorTerms` and `securityGroupSelectorTerms` tags |
| Nodes provisioned but pods still pending | Check taints, tolerations, and node affinity rules |
| Nodes not consolidating | Check `consolidationPolicy` in the NodePool spec |
| Spot interruption not handled | Verify SQS queue exists and Karpenter has permissions to read from it |

## Useful Commands

```bash
# List all Karpenter-managed nodes
kubectl get nodeclaims

# Describe a NodePool
kubectl describe nodepool default

# View Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Check node labels (instance type, AZ, capacity type)
kubectl get nodes --show-labels

# Check which nodes are Spot vs On-Demand
kubectl get nodes -L karpenter.sh/capacity-type

# Force node consolidation by cordoning
kubectl cordon <node-name>
```
