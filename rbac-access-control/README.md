# Lab 2 — Azure RBAC Access Control

Owner · VM Contributor · Reader — Scoped to FS01 Only · Terraform + PowerShell

**Status: completed, then torn down.** The three role assignments were removed with `terraform destroy` after the lab was finished. The files here are the full lab as built, rebuilt from the SOP after the local project folder was deleted.

## Purpose

Lab 1 controlled who can access files *inside* a VM. This lab solves a different problem: controlling who can manage the VM itself from Azure — least privilege at the Azure control plane.

Three personas, three roles, one VM, fully scoped:

| Persona | Role on FS01 | Can do |
| --- | --- | --- |
| SysAdmin | Owner | Full control on FS01, including managing RBAC assignments |
| SupportTech | Virtual Machine Contributor | Start, stop, restart, connect via RDP — cannot delete the VM or manage RBAC |
| Auditor | Reader | View FS01's configuration and status — no actions of any kind |

All three role assignments are scoped to FS01's resource ID only. DC01 and CLIENT01 are in the same resource group but have no assignments in this lab. Azure RBAC operates at the Resource Manager control plane — completely separate from the NTFS permissions inside the VM.

## Prerequisite — Lab 1 must be running first

This lab deploys no new infrastructure: no new VMs, no networking, no resource groups. It only adds 3 role assignments on FS01. Lab 1 (NTFS File Server) must be fully deployed first — `RG-FileServerLab` and `FS01` must exist, and all three Lab 1 VMs must show `VM running`:

```powershell
az vm list -g RG-FileServerLab --query "[].{name:name,status:powerState}" -o table
```

Deploy time is under 1 minute. Role assignments are free — only the Lab 1 VMs incur compute charges.

## Files

```
rbac-lab-terraform/
├── backend.tf                 ← reuses Lab 1 storage account, different state key
├── versions.tf                ← provider version requirements
├── variables.tf               ← three Object ID inputs with no defaults
├── data.tf                    ← reads Lab 1 resource group and FS01 without modifying them
├── rbac.tf                    ← the three role assignments scoped to FS01
├── outputs.tf                 ← VM ID, resource group, role assignment IDs
├── terraform.tfvars.example   ← safe template, commit this
├── terraform.tfvars           ← your real Object IDs, never commit this
├── .gitignore
├── validate-lab.ps1           ← confirms assignments, prints permission matrix, exports report
└── scripts/
    └── 01-get-object-ids.ps1  ← translates user emails to Azure AD Object IDs
```

Remote state reuses Lab 1's storage account (`RG-TerraformState`, container `tfstate`) with its own state key, `rbac-lab.terraform.tfstate`. The Object ID variables have no defaults on purpose — Terraform errors out loudly if they are not provided, instead of assigning roles to placeholder identities.

## How to run

1. **Test users** — you need three existing Azure AD accounts (test accounts, not your own): one for SysAdmin, one for SupportTech, one for Auditor. If your tenant enforces MFA, the test accounts need a Conditional Access exclusion, or use a test tenant without MFA — Step 7 logs in as each test user.
2. **Get the Object IDs:**
   ```powershell
   .\scripts\01-get-object-ids.ps1
   ```
   It prompts for the three UPNs and prints the Object IDs to paste into `terraform.tfvars`.
3. **Configure variables:**
   ```powershell
   Copy-Item terraform.tfvars.example terraform.tfvars
   ```
   Paste the three Object IDs into `terraform.tfvars`. Confirm `resource_group_name = "RG-FileServerLab"` and `vm_name = "FS01"` match Lab 1 exactly (case-sensitive). Open `backend.tf` and replace `REPLACE_WITH_YOUR_LAB1_STORAGE_ACCOUNT_NAME` with the Lab 1 storage account name.
4. **Deploy:**
   ```powershell
   az login
   terraform init
   terraform plan    # Must show exactly 3 resources — no VMs, no networking, no resource groups
   terraform apply   # Type yes — completes in under 1 minute
   ```
   If the plan shows more than 3 resources, stop: `resource_group_name` or `vm_name` does not match Lab 1 exactly.

## Validate

Wait 2–3 minutes for RBAC to propagate, then run:

```powershell
.\validate-lab.ps1
```

It queries the live RBAC state directly (not Terraform state), confirms all three assignments are active, prints a permission matrix, and exports `RBAC_Lab_Report.txt`. RBAC propagation can take up to 10 minutes in some tenants — if validation shows FAIL after 5 minutes, wait and re-run it.

Permission matrix (FS01 scope only):

| Action | Owner | VM Contributor | Reader |
| --- | --- | --- | --- |
| View VM details | Yes | Yes | Yes |
| Start / Stop VM | Yes | Yes | No |
| Connect via RDP | Yes | Yes | No |
| Delete VM | Yes | No | No |
| Manage RBAC roles | Yes | No | No |

## Test as each persona

Log in as each test user in a separate terminal and confirm the expected result. The FAIL results are not errors — they prove role enforcement is working:

- **Auditor (Reader):** `az vm show -g RG-FileServerLab -n FS01` succeeds; `az vm stop -g RG-FileServerLab -n FS01` fails with `AuthorizationFailed`.
- **SupportTech (VM Contributor):** `az vm start -g RG-FileServerLab -n FS01` succeeds; `az role assignment list --scope <FS01 id>` fails with `AuthorizationFailed`.
- **SysAdmin (Owner):** `az vm show` succeeds; `az role assignment list --scope <FS01 id>` succeeds.

Then log back in as your own account (`az login`, `az account show`).

## Teardown

```powershell
# Option A — remove RBAC only, keep Lab 1 VMs running
terraform destroy

# Option B — full teardown, completely done with both labs
terraform destroy
az group delete -n RG-FileServerLab --yes --no-wait
az group show -n RG-FileServerLab 2>&1   # Expect: ResourceGroupNotFound
```

## Troubleshooting

| Problem | Cause | Solution |
| --- | --- | --- |
| `terraform apply`: principal not found | Object ID is wrong or the account was deleted | Re-run `01-get-object-ids.ps1`, update `terraform.tfvars`, re-apply |
| `terraform apply`: resource group not found | Lab 1 is not deployed | Deploy the NTFS lab first — `RG-FileServerLab` must exist |
| validate shows FAIL after 10+ minutes | Role assignment not in Terraform state | Run `terraform state list` — confirm three `azurerm_role_assignment` resources appear; if missing, re-apply |
| `az vm stop` succeeds for Auditor | RBAC still propagating | Wait 5 minutes and retest |
| Plan shows more than 3 resources | `resource_group_name` or `vm_name` mismatch | Check capitalization — `FS01` is not the same as `fs01` |
| MFA prompt when logging in as test user | Tenant enforces MFA | Create a Conditional Access exclusion for test accounts or use a test tenant without MFA |

Source: Skool lab guide "Lab 2 — Azure RBAC Access Control" (Cloud System Admin Labs).
