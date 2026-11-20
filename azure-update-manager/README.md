# Azure Update Manager Lab — Patch Management & Compliance Reporting

> **Status: completed, then torn down.** This lab was run to completion and destroyed with `terraform destroy`. No Azure resources from this lab are currently running.

## Purpose

Unpatched systems are one of the most common root causes of security incidents. The challenge at scale is not patching one server — it is knowing which machines across an environment are missing which patches, enforcing a consistent schedule, and producing documentation that proves compliance to auditors.

Azure Update Manager is the cloud-native replacement for WSUS: agentless for Azure VMs, integrated with Azure Policy for automatic enrollment, with a compliance record per machine and support for both scheduled patching and manual approval workflows.

This lab builds a complete patch management pipeline from zero: infrastructure deployment, policy-based enrollment, maintenance window configuration, on-demand assessment, compliance validation, and structured report export.

## What it deploys

- **Resource group:** `rg-aumlab` (fully standalone — no dependency on Lab 1 or Lab 2)
- **VMs:** DC01 (domain controller), WS01, WS02 (member servers) — Windows Server 2022 Datacenter, Standard_B2s
- **Domain:** `aumlab.local` (NetBIOS `AUMLAB`); DC01 promoted via Custom Script Extension, WS01/WS02 domain-joined after promotion (DC01 static private IP `10.0.1.4`)
- **Network:** VNet `vnet-aumlab` (10.0.0.0/16), subnet `snet-aumlab` (10.0.1.0/24), NSG `nsg-aumlab` — inbound RDP 3389 from your IP only
- **Key Vault:** stores the VM admin password as a secret, RBAC permission model (`enable_rbac_authorization = true`)
- **Azure Policy:** built-in policy `59efceea` auto-enrolls every VM in the resource group into periodic patch assessment (assessment only — it does not apply patches)
- **Maintenance Configuration:** `aum-weekly-patches` — weekly window, 02:00 Eastern, 3 hours, classifications Critical / Security / UpdateRollup, reboot only if required
- **Maintenance Assignments:** the weekly schedule linked to each of the three VMs

Deploy time: 15–20 minutes (DC01 domain promotion is the longest step).
Cost: ~$0.17/hr total (~$4/day) — always run `terraform destroy` when finished.

## Structure

```text
azure-update-manager/
├── backend.tf                         ← remote state (key aum-lab.tfstate)
├── versions.tf                        ← provider requirements (azurerm ~> 3.100, random ~> 3.6)
├── variables.tf                       ← all input variables
├── main.tf                            ← root module wiring all 4 child modules
├── outputs.tf                         ← VM public IPs and Key Vault name
├── terraform.tfvars.example           ← safe template, commit this
├── .gitignore
├── modules/
│   ├── networking/main.tf             ← VNet, subnet, NSG, NSG-subnet association
│   ├── keyvault/main.tf               ← Key Vault with RBAC model + admin password secret
│   ├── compute/main.tf                ← 3 VMs, domain promotion, domain join
│   └── update-manager/main.tf         ← Azure Policy + Maintenance Config + 3 Assignments
└── scripts/
    └── validate-lab.ps1               ← compliance validation + JSON report export
```

## Prerequisites

- Terraform >= 1.5.0, Azure CLI, PowerShell 7+
- Az PowerShell module (`Install-Module Az -Scope CurrentUser -Force`) for `validate-lab.ps1`
- Register resource providers before applying — both must show `Registered`:
  - `az provider register --namespace Microsoft.Maintenance`
  - `az provider register --namespace Microsoft.GuestConfiguration`

## How to run

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars:
#   allowed_rdp_ip = your current public IP from whatismyip.com, format 1.2.3.4/32

# Edit modules/update-manager/main.tf:
#   Update start_date_time to any future date — if this date is in the past, terraform plan fails

# Edit backend.tf:
#   Replace REPLACE_WITH_YOUR_STORAGE_ACCOUNT_NAME with your storage account name
#   (reuse the Lab 1 / Lab 2 RG-TerraformState storage account; the state key
#   aum-lab.tfstate is unique to this lab)

# Set the admin password as an environment variable — never in a file
$env:TF_VAR_admin_password = "<your password>"   # min 12 chars, upper + lower + number + symbol

az login
terraform init
terraform plan -out=aum-lab.tfplan
# Review — expect: 3 VMs, 1 VNet + NSG + subnet + association, 1 Key Vault,
# 1 Maintenance Configuration, 3 Maintenance Assignments, 1 Policy Assignment

terraform apply aum-lab.tfplan
# Takes 15-20 minutes — DC01 domain promotion is the longest step
```

Notes from the lab guide:

- The DSRM password for the DC01 promotion extension is passed in as a sensitive variable (`TF_VAR_dsrm_password`), never hardcoded. The SOP prints it hardcoded as a lab-only shortcut; this repo parameterizes it instead, since the repo is public.
- `admin_password` is marked `sensitive` in Terraform and is set only via the `TF_VAR_admin_password` environment variable. No `terraform.tfvars` with real values is committed to this repo.

## Trigger assessment and validate

After deployment, trigger an on-demand assessment on each VM immediately (the Azure Policy runs assessments on its own ~24-hour schedule, but triggering manually surfaces compliance data right now):

```powershell
$subId = az account show --query id -o tsv

foreach ($vm in @("DC01","WS01","WS02")) {
    az rest --method POST `
        --url "https://management.azure.com/subscriptions/$subId/resourceGroups/rg-aumlab/providers/Microsoft.Compute/virtualMachines/$vm/assessPatches?api-version=2022-03-01"
    Write-Host "Assessment triggered: $vm"
}

# Wait 5-10 minutes, then validate
pwsh ./scripts/validate-lab.ps1 -ResourceGroup "rg-aumlab" -SubscriptionId $subId
```

`validate-lab.ps1` prints PASS/FAIL per machine and exports `aum-compliance-report.json` (machine-readable, for a SIEM, ServiceNow, or compliance dashboard).

- **PASS** = the assessment ran successfully and no Critical or Security patches are missing.
- **FAIL with Critical missing > 0 on a brand-new VM is expected** — the machine has patches outstanding. It proves the assessment is working correctly. Apply patches via the maintenance window, then re-run validation to confirm.

### Portal verification checklist

- Azure Update Manager → Machines → all 3 VMs show as Assessed
- Maintenance Configurations → `aum-weekly-patches` → all 3 VMs are linked
- Policy → Assignments → periodic assessment policy shows Applied on `rg-aumlab`

## Teardown

```powershell
terraform destroy -auto-approve

# Verify everything is removed
az group show --name rg-aumlab 2>&1
# Expected: ResourceGroupNotFound
```

## Source

Rebuilt verbatim from the lab guide ("aum-lab-complete-sop"), Cloud System Admin Labs series, Lab 3 — Azure Update Manager.
