# prometheus-stack

Prometheus + Grafana + Alertmanager for cluster monitoring and alerting. Deploys the full [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) with production-ready defaults: 15-day retention, persistent storage, daily Slack alerts, and pre-configured recording rules.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- Storage class available (`gp3`)
- (Optional) Slack webhook URL for alert notifications
- (Optional) SMTP server for email alerts
- (Optional) PagerDuty routing key for critical alerts

## Install

```bash
helm dependency build
helm install monitoring . -n monitoring --create-namespace
```

Apply custom alert rules and dashboards:

```bash
kubectl apply -f manifests/alert-rules.yaml
kubectl apply -f manifests/grafana-dashboards.yaml
```

To enable Alertmanager receivers (Slack, Email, PagerDuty), update the secrets in `manifests/alertmanager-config.yaml` with real values, then:

```bash
kubectl apply -f manifests/alertmanager-config.yaml
```

## Verify

```bash
kubectl get pods -n monitoring
```

All pods should be `Running` and `1/1` (or `2/2` for Prometheus).

Access Grafana (default credentials `admin` / `admin`):

```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```

Open http://localhost:3000.

Access Prometheus:

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090 -n monitoring
```

Open http://localhost:9090.

Access Alertmanager:

```bash
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093 -n monitoring
```

Open http://localhost:9093.

## Upgrade

```bash
helm dependency update
helm upgrade monitoring . -n monitoring
```

After upgrading, re-apply any custom manifests if CRD versions changed:

```bash
kubectl apply -f manifests/
```

## Uninstall

```bash
helm uninstall monitoring -n monitoring
kubectl delete pvc -n monitoring -l app.kubernetes.io/name=prometheus
kubectl delete pvc -n monitoring -l app.kubernetes.io/name=grafana
```

> **Note:** CRDs are not removed by `helm uninstall`. To fully clean up:
> ```bash
> kubectl delete crd prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com podmonitors.monitoring.coreos.com alertmanagerconfigs.monitoring.coreos.com probes.monitoring.coreos.com
> ```

---

## Alertmanager Configuration

Alertmanager handles alert routing, grouping, silencing, and notification delivery. Configuration lives in `values.yaml` (inline) and in `manifests/alertmanager-config.yaml` (AlertmanagerConfig CRD).

### Receivers

#### Slack

Add a Slack incoming webhook URL. In `values.yaml`:

```yaml
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
          - api_url: "https://hooks.slack.com/services/T00/B00/XXXX"
            channel: "#alerts"
            send_resolved: true
            title: '[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
            text: '{{ .CommonAnnotations.description }}'
```

#### PagerDuty

```yaml
receivers:
  - name: pagerduty
    pagerduty_configs:
      - routing_key: "<YOUR_PAGERDUTY_ROUTING_KEY>"
        severity: '{{ .CommonLabels.severity }}'
        description: '{{ .CommonAnnotations.description }}'
```

#### Email

```yaml
receivers:
  - name: email
    email_configs:
      - to: "oncall@example.com"
        from: "alertmanager@example.com"
        smarthost: "smtp.example.com:587"
        auth_username: "alertmanager@example.com"
        auth_password: "<SMTP_PASSWORD>"
        require_tls: true
        send_resolved: true
```

#### Using the AlertmanagerConfig CRD (recommended)

For a more Kubernetes-native approach, use the `AlertmanagerConfig` resource in `manifests/alertmanager-config.yaml`. This keeps secrets in Kubernetes Secrets and supports per-namespace routing. See the file for a complete example with Slack, Email, and PagerDuty receivers.

### PagerDuty Integration

PagerDuty receives P1/P2 critical alerts via the Events API v2. The integration uses a **routing key** (also called integration key), which is obtained from a PagerDuty service.

**How it works:**

1. Create a service in PagerDuty (e.g., "Kubernetes Production").
2. Add an **Events API v2** integration to the service.
3. Copy the **Integration Key** (routing key) from the integration.
4. Store it in the Kubernetes secret `alertmanager-pagerduty-secret`:

```bash
kubectl create secret generic alertmanager-pagerduty-secret \
  -n monitoring \
  --from-literal=routing-key="YOUR_PAGERDUTY_ROUTING_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
```

When a critical alert fires, Alertmanager sends an event to PagerDuty with the alert's priority, severity, namespace, and description. PagerDuty creates an incident and notifies the on-call responder. When the alert resolves, Alertmanager sends a resolve event and PagerDuty auto-resolves the incident.

### Severity Routing (P1–P5)

All alerts carry `severity`, `priority`, and `team` labels. Routing is based on severity:

| Priority | Severity | Description | Action | Notification Channels | Repeat Interval |
|---|---|---|---|---|---|
| **P1** | critical | Cluster down, node not ready | Immediate response required | PagerDuty + Slack | 15m |
| **P2** | critical | High error rate, crash loops, PVC full | Urgent investigation | PagerDuty + Slack | 15m |
| **P3** | warning | High CPU/memory, cert expiring, high latency | Needs attention during business hours | Slack only | 4h |
| **P4** | info | Pod pending, replica mismatch | Awareness, no immediate action | Email only | 4h |
| **P5** | info | Cert expiring 30 days, disk > 70% | Low priority, plan remediation | Email only | 4h |

Alerts are grouped by `alertname`, `namespace`, and `pod` with a 30s group wait and 5m group interval.

An **inhibition rule** suppresses warning alerts when a critical alert is already firing for the same `alertname` and `namespace`, preventing duplicate noise.

### Configuring in values.yaml

To configure PagerDuty inline in `values.yaml` instead of using the CRD:

```yaml
alertmanager:
  config:
    route:
      receiver: slack-notifications
      group_by: ["alertname", "namespace", "pod"]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - receiver: pagerduty-critical
          matchers:
            - severity = "critical"
          repeat_interval: 15m
          continue: true
        - receiver: slack-notifications
          matchers:
            - severity = "critical"
        - receiver: slack-notifications
          matchers:
            - severity = "warning"
        - receiver: email-notifications
          matchers:
            - severity = "info"
    inhibit_rules:
      - source_matchers:
          - severity = "critical"
        target_matchers:
          - severity = "warning"
        equal: ["alertname", "namespace"]
    receivers:
      - name: slack-notifications
        slack_configs:
          - api_url: "https://hooks.slack.com/services/T00/B00/XXXX"
            channel: "#alerts"
            send_resolved: true
      - name: pagerduty-critical
        pagerduty_configs:
          - routing_key: "<YOUR_PAGERDUTY_ROUTING_KEY>"
            severity: '{{ .CommonLabels.severity }}'
            description: '[{{ .CommonLabels.priority }}] {{ .CommonLabels.alertname }}'
      - name: email-notifications
        email_configs:
          - to: "oncall-team@example.com"
            from: "alertmanager@example.com"
            smarthost: "smtp.example.com:587"
            auth_username: "alertmanager@example.com"
            auth_password: "<SMTP_PASSWORD>"
            require_tls: true
            send_resolved: true
```

### Routes

Routes determine which receiver handles each alert based on label matchers. The `continue: true` flag on the PagerDuty route allows critical alerts to also reach Slack:

```yaml
route:
  receiver: slack-notifications       # default receiver
  group_by: ["alertname", "namespace", "pod"]
  routes:
    - receiver: pagerduty-critical    # P1/P2: PagerDuty first...
      matchers:
        - severity = "critical"
      continue: true                  # ...then continue to next match
    - receiver: slack-notifications   # P1/P2: also Slack; P3: Slack only
      matchers:
        - severity =~ "critical|warning"
    - receiver: email-notifications   # P4/P5: email only
      matchers:
        - severity = "info"
```

### Custom Alert Rules (PrometheusRule)

Create a `PrometheusRule` resource to define custom alerts. The resource must have labels matching the Prometheus `ruleSelector` (by default, `release: monitoring`).

The file `manifests/alert-rules.yaml` includes these production-ready alerts:

| Alert | Condition | Priority | Severity | Channels |
|---|---|---|---|---|
| **ClusterDown** | All nodes NotReady | P1 | critical | PagerDuty + Slack |
| **NodeNotReady** | Node NotReady for 5m | P1 | critical | PagerDuty + Slack |
| **HighErrorRate** | 5xx > 5% for 5m | P2 | critical | PagerDuty + Slack |
| **PodCrashLooping** | > 5 restarts in 15m | P2 | critical | PagerDuty + Slack |
| **PVCAlmostFull** | PVC > 90% full for 5m | P2 | critical | PagerDuty + Slack |
| **HighCPU** | CPU > 80% for 5m | P3 | warning | Slack |
| **HighMemory** | Memory > 85% for 5m | P3 | warning | Slack |
| **CertificateExpiringSoon** | Expires in < 7 days | P3 | warning | Slack |
| **HighLatency** | p99 > 1s for 5m | P3 | warning | Slack |
| **PodPending** | Pending > 5m | P4 | info | Email |
| **DeploymentReplicasMismatch** | Replicas ≠ ready for 5m | P4 | info | Email |
| **CertificateExpiring30Days** | Expires in < 30 days | P5 | info | Email |
| **DiskUsageHigh** | Disk > 70% for 5m | P5 | info | Email |

Apply them:

```bash
kubectl apply -f manifests/alert-rules.yaml
```

Verify rules are loaded:

```bash
kubectl get prometheusrules -n monitoring
# Check in Prometheus UI → Status → Rules
```

### Testing Alerts

**Validate alert rules syntax with promtool:**

```bash
# Download promtool (included with Prometheus)
promtool check rules manifests/alert-rules.yaml
```

**Test alert routing with amtool:**

```bash
# Port-forward Alertmanager
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093 -n monitoring &

# Check which receiver matches a critical alert
amtool config routes test --config.file=<(amtool config show --alertmanager.url=http://localhost:9093) \
  severity=critical priority=P1

# Show the full routing tree
amtool config routes show --alertmanager.url=http://localhost:9093

# Send a test alert to verify end-to-end delivery
amtool alert add TestAlert \
  --alertmanager.url=http://localhost:9093 \
  --label severity=critical \
  --label priority=P1 \
  --label team=platform \
  --annotation summary="Test P1 alert" \
  --annotation description="Testing PagerDuty integration"

# Remove the test alert
amtool alert expire TestAlert --alertmanager.url=http://localhost:9093
```

**Verify in PagerDuty:**

After sending a test alert, check the PagerDuty service for a new incident. Confirm it auto-resolves after expiring the alert.

### Writing Your Own Alert

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-app-alerts
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
    - name: my-app
      rules:
        - alert: MyAppDown
          expr: up{job="my-app"} == 0
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "my-app is down"
            description: "No healthy instances of my-app for 2 minutes."
```

---

## Grafana Dashboards

### Importing Dashboards by ID

1. Open Grafana → **Dashboards** → **New** → **Import**.
2. Enter the dashboard ID and click **Load**.
3. Select the Prometheus datasource and click **Import**.

### Recommended Dashboard IDs

| Dashboard | ID | Description |
|---|---|---|
| Node Exporter Full | **1860** | Detailed node metrics (CPU, memory, disk, network) |
| Kubernetes Cluster | **6417** | Cluster-wide overview (nodes, pods, deployments) |
| NGINX Ingress Controller | **9614** | Request rate, latency, error rate per ingress |
| CoreDNS | **5926** | DNS query rate, latency, cache hit ratio |
| Pod Resources | **6879** | Per-pod CPU, memory, network usage |

### Custom Dashboards via ConfigMap

Grafana's sidecar automatically imports dashboards from ConfigMaps labeled `grafana_dashboard: "1"`. See `manifests/grafana-dashboards.yaml` for a Cluster Overview dashboard example.

Apply it:

```bash
kubectl apply -f manifests/grafana-dashboards.yaml
```

The dashboard appears in Grafana within ~30 seconds.

### Configuring Grafana Datasources

The default Prometheus datasource is auto-configured. To add additional datasources, use `values.yaml`:

```yaml
grafana:
  additionalDataSources:
    - name: CloudWatch
      type: cloudwatch
      access: proxy
      jsonData:
        authType: default
        defaultRegion: us-east-1

    - name: Loki
      type: loki
      url: http://loki-gateway.logging.svc.cluster.local
      access: proxy
```

---

## Troubleshooting

| Problem | Action |
|---|---|
| Grafana not loading | Check PVC is `Bound`: `kubectl get pvc -n monitoring` |
| Prometheus targets down | Port-forward to `:9090` and check `/targets` |
| Alerts not firing | Verify PrometheusRule labels match `ruleSelector` — check `/rules` in Prometheus UI |
| Alerts firing but no notification | Check Alertmanager config: port-forward to `:9093` → Status → check receivers |
| High memory on Prometheus | Reduce `retention` or add `--storage.tsdb.retention.size` limit |
| Dashboard not appearing | Verify ConfigMap label `grafana_dashboard: "1"` and namespace `monitoring` |
| Grafana "datasource not found" | Check datasource name matches what dashboards expect (usually `Prometheus`) |

### Checking Alert Status

```bash
# List all PrometheusRules
kubectl get prometheusrules -A

# Check which alerts are firing
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093 -n monitoring
# Open http://localhost:9093/#/alerts
```

### Checking Prometheus Targets

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090 -n monitoring
# Open http://localhost:9090/targets
```

## Useful Commands

```bash
# Cluster resource usage
kubectl top nodes
kubectl top pods -A

# Access all monitoring UIs
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090 -n monitoring
kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093 -n monitoring

# Check Prometheus storage usage
kubectl exec -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0 -- df -h /prometheus

# Reload Prometheus config (after ConfigMap changes)
kubectl exec -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0 -- kill -HUP 1

# Query Prometheus from CLI
kubectl exec -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0 -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=up' | head -c 500

# List all ServiceMonitors
kubectl get servicemonitors -A

# List all PodMonitors
kubectl get podmonitors -A
```

## File Structure

```
prometheus-stack/
├── Chart.yaml
├── values.yaml
├── README.md
├── charts/
│   └── kube-prometheus-stack-65.1.0.tgz
└── manifests/
    ├── alert-rules.yaml           # PrometheusRule with custom alerts
    ├── alertmanager-config.yaml   # AlertmanagerConfig + receiver secrets
    └── grafana-dashboards.yaml    # Custom Grafana dashboard ConfigMap
```
