# victoria-metrics

VictoriaMetrics — a high-performance, drop-in Prometheus replacement that uses up to 7x less memory and 7x less disk while supporting full PromQL.

## Description

VictoriaMetrics is a time-series database and monitoring solution that is fully compatible with Prometheus. It accepts data via Prometheus remote_write, scrapes targets using VMAgent, evaluates alerting rules with VMAlert, and serves PromQL queries — all while consuming a fraction of the resources.

Key advantages over Prometheus:
- **7x less memory** — efficient compression and storage engine
- **7x less disk** — advanced data compression (up to 0.4 bytes per data point vs ~3 bytes for Prometheus)
- **Faster queries** — optimized PromQL engine, especially for high-cardinality data
- **Long-term storage** — designed for months/years of retention without performance degradation
- **Drop-in replacement** — supports PromQL, Prometheus remote_write, and Grafana datasource

This stack deploys:
- **VMSingle** — single-node VictoriaMetrics database (90-day retention, 100Gi storage)
- **VMAgent** — scrapes metrics from targets (replaces Prometheus scraper)
- **VMAlert** — evaluates alerting/recording rules
- **Alertmanager** — routes alerts to Slack, PagerDuty, etc.

Grafana is disabled because the existing Grafana from `prometheus-stack` can be pointed at VictoriaMetrics as a Prometheus-type datasource.

## When to Use

- You need **long retention** (90 days or more) and Prometheus is running out of memory/disk
- You have **high-cardinality** metrics (many labels, many series) and Prometheus is slow
- You want to **reduce monitoring costs** — less CPU, memory, and storage for the same data
- You want a **drop-in replacement** that works with existing Grafana dashboards and PromQL alerts
- You want to run VictoriaMetrics **alongside Prometheus** during migration (Prometheus remote_writes to VM)

## Comparison with Alternatives

| Feature | VictoriaMetrics | Prometheus | Thanos |
|---|---|---|---|
| **Type** | TSDB + Monitoring stack | TSDB + Monitoring stack | Multi-cluster Prometheus |
| **Memory Usage** | ~7x less | Baseline | Similar to Prometheus |
| **Disk Usage** | ~7x less | Baseline | Uses object storage (S3) |
| **Query Speed** | Faster (optimized engine) | Standard | Slower (cross-cluster) |
| **Long-term Storage** | ✅ Native (months/years) | ❌ Degrades after weeks | ✅ Via S3 |
| **High Cardinality** | ✅ Handles well | ❌ OOM risk | ✅ With store gateway |
| **PromQL** | ✅ Full + extensions (MetricsQL) | ✅ Native | ✅ Full |
| **Multi-cluster** | ✅ VMCluster mode | ❌ Single cluster | ✅ Primary use case |
| **Ecosystem** | Growing | Largest | Prometheus-dependent |
| **Complexity** | Low | Low | High |
| **Best for** | Long retention, cost savings | Standard monitoring | Multi-cluster federation |

**Choose VictoriaMetrics when** you need long retention (90d+), have high cardinality, or want to cut monitoring costs. Choose Prometheus if you want the largest ecosystem and 15-day retention is enough. Choose Thanos if you need multi-cluster federation with S3-backed long-term storage.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- Storage class `gp3` available
- (Optional) Existing Grafana to add VictoriaMetrics as a datasource

## Install

```bash
helm dependency build
helm install victoria-metrics . -n monitoring --create-namespace
```

## Verify

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/instance=victoria-metrics
kubectl get svc -n monitoring | grep victoria
```

Test that VMSingle is accepting queries:

```bash
kubectl port-forward svc/vmsingle-victoria-metrics 8428:8428 -n monitoring
curl http://localhost:8428/api/v1/query?query=up
```

## Configure

### Add VictoriaMetrics as a Grafana Datasource

In your existing Grafana, add a new datasource:
- **Type:** Prometheus
- **URL:** `http://vmsingle-victoria-metrics-victoria-metrics-k8s-stack.monitoring.svc:8428`
- **Access:** Server

All existing Prometheus dashboards will work without modification.

### Remote Write from Prometheus to VictoriaMetrics

If running both Prometheus and VictoriaMetrics during migration, add to your `prometheus-stack` values:

```yaml
kube-prometheus-stack:
  prometheus:
    prometheusSpec:
      remoteWrite:
        - url: http://vmsingle-victoria-metrics-victoria-metrics-k8s-stack.monitoring.svc:8428/api/v1/write
```

### Adjust Retention and Storage

```yaml
victoria-metrics-k8s-stack:
  vmsingle:
    spec:
      retentionPeriod: "180d"
      storage:
        resources:
          requests:
            storage: 200Gi
```

### Configure Alertmanager

```yaml
victoria-metrics-k8s-stack:
  alertmanager:
    config:
      route:
        receiver: slack
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 4h
      receivers:
        - name: slack
          slack_configs:
            - api_url: "https://hooks.slack.com/services/CHANGE_ME"
              channel: "#alerts"
              send_resolved: true
```

## Upgrade

```bash
helm upgrade victoria-metrics . -n monitoring
```

## Uninstall

```bash
helm uninstall victoria-metrics -n monitoring
kubectl delete pvc -n monitoring -l app.kubernetes.io/instance=victoria-metrics
```

> **Warning:** Deleting PVCs will permanently remove all stored metrics data.

## Troubleshooting

```bash
# VMSingle logs
kubectl logs -n monitoring -l app.kubernetes.io/name=vmsingle

# VMAgent logs (scraping issues)
kubectl logs -n monitoring -l app.kubernetes.io/name=vmagent

# VMAlert logs (alerting issues)
kubectl logs -n monitoring -l app.kubernetes.io/name=vmalert
```

- **VMSingle OOM** — increase memory limits or reduce `retentionPeriod`. Check cardinality: `curl http://localhost:8428/api/v1/status/tsdb`.
- **VMAgent not scraping targets** — port-forward VMAgent and check `/targets`: `kubectl port-forward svc/vmagent-victoria-metrics 8429:8429 -n monitoring`.
- **Grafana shows no data** — verify the datasource URL points to VMSingle service and the port is `8428`.
- **PVC not binding** — check that the `gp3` StorageClass exists: `kubectl get sc`.
- **Alerts not firing** — check VMAlert is running and Alertmanager is reachable: `kubectl get pods -n monitoring | grep vmalert`.

## Useful Commands

```bash
# Check VictoriaMetrics storage usage
kubectl exec -n monitoring deploy/vmsingle-victoria-metrics -- df -h /storage

# Check active time series count
curl -s http://localhost:8428/api/v1/status/tsdb | jq '.data.totalSeries'

# Check VMAgent scrape targets
kubectl port-forward svc/vmagent-victoria-metrics 8429:8429 -n monitoring
# Open http://localhost:8429/targets

# Compare resource usage with Prometheus
kubectl top pods -n monitoring
```
