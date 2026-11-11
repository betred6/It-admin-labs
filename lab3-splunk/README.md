# Lab 3 — Splunk SIEM & Log Analysis on Azure

A Windows Server VM ships its event logs into a Splunk indexer on Azure, where I ran SPL searches, built a security dashboard, and configured a detection alert — the core Tier-1 SOC workflow.

**Skills:** Splunk Enterprise · Universal Forwarder · SPL · dashboards · alerting · Azure VMs
**Aligned with:** CompTIA Security+, CySA+, Splunk Core Certified User (SPLK-1001)

## Architecture

```mermaid
flowchart LR
    subgraph AZ["Microsoft Azure — East US"]
        TV["testVm<br/>Windows Server 2025<br/>Universal Forwarder 10.2.2"]
        SV["splunkvm<br/>Ubuntu 24.04<br/>Splunk Enterprise 10.2.2"]
        TV -- "Security / System / Application logs<br/>TCP 9997" --> SV
        SV --> IDX[("Index: windows_logs<br/>1,990,392 events")]
        IDX --> DASH["Dashboard<br/>Windows Security Overview"]
        IDX --> ALERT["Alert<br/>High Privileged Logon Count"]
    end
```

## What was built

1. **Indexer** — Splunk Enterprise 10.2.2 on `splunkvm`, receiver enabled on port **9997**, `windows_logs` index created, Splunk set to start on boot.
2. **Forwarder** — Universal Forwarder 10.2.2 on `testVm`, configured to forward the Security, System, and Application Windows event logs into the `windows_logs` index.
3. **Log generation** — service restarts generated 7036 events; failed-logon activity generated 4625s; normal admin activity produced 4624/4672.
4. **Verification** — 1,990,392 events searchable in Splunk (all-time count, November 10, 2026). While the indexer VM was stopped, testVm kept logging and the forwarder delivered the backlog when the indexer came back — the index grew from 112,428 events at build time to 1,990,392:

| EventCode | Meaning | Count |
|-----------|---------|-------|
| 4624 | Successful logon | 120,566 |
| 4625 | Failed logon | 495,862 |
| 4672 | Special privileges assigned to new logon | 120,530 |
| 7036 | Service state change | 14,691 |

The failed logons break down by target account (`Account_Name`): Administrator was attempted 216,799 times, alongside a spray list of common guesses (NOUSER, azureuser, azureadmin, sysadmin, vmadmin, itadmin, and others) — automated password-spraying traffic against the VM, collected by the lab pipeline.

## SPL queries used

```spl
| metadata type=hosts index=windows_logs
index=windows_logs | stats count
index=windows_logs EventCode=4625 | stats count by Account_Name
```

## Dashboard — "Windows Security Overview"

Four panels over the last 24 hours:

1. **Logon Events Over Time** — `index=windows_logs EventCode=4624 OR EventCode=4625 | timechart count by EventCode`
2. **Failed Logons by User** — `index=windows_logs EventCode=4625 | stats count by Account_Name | sort -count | head 10`
3. **Service State Changes** — `index=windows_logs EventCode=7036 | timechart count by Service_Name`
4. **Privileged Logons** — `index=windows_logs EventCode=4672 | stats count`

## Alert — "High Privileged Logon Count"

- **Search:** `index=windows_logs EventCode=4672 | stats count by TargetUserName | where count > 5`
- **Schedule:** every 5 minutes, window −5m → now
- **Logic:** fires when one user accumulates more than 5 special-privilege logons in 5 minutes — possible privilege misuse or attack.

## Screenshots

![Event count in the windows_logs index](screenshots/01-event-count.png)
*1,990,392 events in the `windows_logs` index (All time)*

![Host metadata for testVm](screenshots/02-host-metadata.png)
*testVm — the host feeding the index, still live*

![Events by EventCode](screenshots/03-eventcode-counts.png)
*Event counts by EventCode, biggest first (4625 failed logons on top)*

![Failed logons by account](screenshots/04-failed-logons-by-account.png)
*Failed logons by target account — Administrator was the top target*

![Forwarder service on testVm](screenshots/05-forwarder-service.png)
*SplunkForwarder service running on testVm*

![Forwarder outputs.conf](screenshots/05-forwarder-config.png)
*outputs.conf — the forwarder sends to splunkvm on TCP 9997*

![Receiver port 9997 enabled](screenshots/06-receiver-9997.png)
*Splunk receiver listening on port 9997 — Enabled*

![Windows Security Overview dashboard](screenshots/07-dashboard.png)
*Windows Security Overview — all four panels live*

![Alert settings](screenshots/08-alert-config.png)
*High Privileged Logon Count — alert settings*

## What I'd do next

- Add Sysmon for richer endpoint telemetry.
- Build a brute-force detection: burst of 4625s followed by a successful 4624.
- Forward from a second Windows host and compare logon patterns across hosts.
