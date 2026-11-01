# Vault

HashiCorp Vault — secrets management with dynamic secrets, PKI, and encryption as a service. Deployed in HA mode with Raft storage on persistent volumes.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- Storage class (`gp3`) for persistent volumes

## Install

```bash
helm dependency build
helm install vault . -n vault --create-namespace
```

Initialize Vault (**save the unseal keys and root token securely**):

```bash
kubectl exec -n vault vault-0 -- vault operator init -key-shares=5 -key-threshold=3
```

Unseal each pod (repeat with 3 different keys):

```bash
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>
```

For HA, join and unseal the other pods:

```bash
kubectl exec -n vault vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault vault-1 -- vault operator unseal <key1>
kubectl exec -n vault vault-1 -- vault operator unseal <key2>
kubectl exec -n vault vault-1 -- vault operator unseal <key3>
# Repeat for vault-2
```

## Verify

```bash
kubectl get pods -n vault
kubectl exec -n vault vault-0 -- vault status
```

All pods should be `Running 1/1`. Vault status should show `Sealed: false`.

Check HA peers:

```bash
kubectl exec -n vault vault-0 -- vault operator raft list-peers
```

Access the UI:

```bash
kubectl port-forward svc/vault-ui 8200:8200 -n vault
```

Open <http://localhost:8200>.

## Upgrade

```bash
helm dependency update
helm upgrade vault . -n vault
```

> **Note:** After upgrading, pods restart and Vault will be sealed. You must unseal each pod again.

## Uninstall

```bash
helm uninstall vault -n vault
kubectl delete pvc -n vault -l app.kubernetes.io/name=vault
```

## Troubleshooting

| Problem | Action |
|---|---|
| Pods stuck at `0/1` | Vault is sealed — unseal it with `vault operator unseal` |
| HA not working | `kubectl exec -n vault vault-0 -- vault operator raft list-peers` |
| Permission denied | Check Vault policies: `vault policy list` |
| Pod restarted and sealed | Unseal again (or configure auto-unseal with AWS KMS) |
| Storage errors | Check PVC status: `kubectl get pvc -n vault` |

## Useful Commands

```bash
# Check Vault status
kubectl exec -n vault vault-0 -- vault status

# List secret engines
kubectl exec -n vault vault-0 -- vault secrets list

# Write a secret
kubectl exec -n vault vault-0 -- vault kv put secret/myapp key=value

# Read a secret
kubectl exec -n vault vault-0 -- vault kv get secret/myapp

# List HA peers
kubectl exec -n vault vault-0 -- vault operator raft list-peers

# View Vault logs
kubectl logs -n vault vault-0

# Enable a new secret engine
kubectl exec -n vault vault-0 -- vault secrets enable -path=kv kv-v2
```
