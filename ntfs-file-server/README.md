# Lab 1 — NTFS File Server Lab

Active Directory · NTFS Permissions · SMB File Services · Group Policy · Terraform · PowerShell

> **Status:** this lab was completed. The VMs are now deallocated (Stopped) — no compute charges while stopped.

## Purpose

Every organization running Windows infrastructure faces the same challenge: controlling who can access what data. Finance data should only be readable by Finance staff. HR files should be invisible to Sales. IT staff need administrative access everywhere to do their jobs.

The solution is a Windows File Server backed by Active Directory groups with NTFS permissions. This lab builds that from scratch using modern cloud infrastructure and Infrastructure as Code.

- **Domain:** lab.local
- **Region:** Central US
- **Deploy time:** 10–15 min (Terraform) + 15–20 min (configure-lab.ps1)
- **Cost:** ~$0.15–$0.25/hr while all three VMs are running

## Architecture

| Component | What it does |
|---|---|
| DC01 | Domain Controller — Active Directory, DNS, Group Policy. Static private IP 10.0.1.4 so FS01/CLIENT01 DNS never breaks after restarts. |
| FS01 | File Server — hosts the four SMB shares with NTFS permissions enforced per security group. |
| CLIENT01 | Windows 11 workstation where test users log in to exercise the full permission chain. |
| VNet (10.0.0.0/16) / Subnet (10.0.1.0/24) | Single VNet, one subnet — all three VMs reach each other on private IPs. |
| NSG — Allow RDP from your IP only | Inbound port 3389 restricted to your IP. All other inbound traffic is implicitly denied. |
| Azure Key Vault (RBAC model) | Stores the VM admin password so it never appears in a file, CLI argument, or terminal history. `configure-lab.ps1` retrieves it at runtime. |
| Public IPs on all three VMs | For RDP access from your machine. |

## Test users

The five test users represent a real org chart scenario. Group membership drives NTFS permissions.

| User | Group | Access |
|---|---|---|
| Sarah Jones (`sarah.jones`) | GRP_Finance | Finance read/write |
| Mike Brown (`mike.brown`) | GRP_Finance | Finance read/write |
| Lisa White (`lisa.white`) | GRP_HR | HR read/write, Finance read-only |
| John Smith (`john.smith`) | GRP_IT | Full Control everywhere |
| Tom Davis (`tom.davis`) | GRP_Sales | No access to Finance or HR data |

- **OUs:** Lab Users, Lab Computers, Lab Groups
- **Groups:** GRP_Finance, GRP_HR, GRP_Sales, GRP_IT
- **Test user password:** one shared password for all five test users. Set it with `$env:LAB_TEST_USER_PASSWORD` before running `configure-lab.ps1`, or you will be prompted for it. It is never stored in the repo (the lab guide's example password is not used here).

## Shares and NTFS permissions

Four folders under `C:\Shares`, shared as SMB shares. Share-level permission is **Everyone Full Control — intentional**. Real security comes from NTFS, not the share. `(OI)(CI)` = Object Inherit + Container Inherit.

| Share | NTFS permissions |
|---|---|
| Finance | GRP_Finance Modify, GRP_HR Read, GRP_IT Full Control, BUILTIN\Administrators Full Control |
| HR | GRP_HR Modify, GRP_IT Full Control, BUILTIN\Administrators Full Control |
| Sales | GRP_Sales Modify, GRP_IT Full Control, BUILTIN\Administrators Full Control |
| IT | GRP_IT Full Control, BUILTIN\Administrators Full Control |

## Files

```
ntfs-file-server/
├── backend.tf                   ← remote state — points to Azure Blob Storage
├── versions.tf                  ← provider versions Terraform downloads
├── variables.tf                 ← all input variables including admin_password
├── main.tf                      ← VMs, VNet, NSG, NICs, public IPs
├── keyvault.tf                  ← Key Vault + secret + RBAC assignment
├── outputs.tf                   ← IPs and Key Vault name printed after apply
├── terraform.tfvars.example     ← safe template, safe to commit
├── .gitignore                   ← prevents sensitive files from being committed
├── configure-lab.ps1            ← the only script you run manually
└── scripts/
    ├── 00-promote-dc.ps1        ← DC01: installs AD DS, promotes to domain controller
    ├── 01-create-ad-users-groups.ps1  ← DC01: creates OUs, groups, test users
    ├── 02-configure-shares-and-permissions.ps1  ← FS01: SMB shares + NTFS ACLs
    ├── 03-configure-rdp-gpo.ps1 ← DC01: creates RDP Group Policy Object
    ├── 04-domain-join.ps1       ← FS01 and CLIENT01: joins both to lab.local
    ├── 05-verify-ad.ps1         ← DC01: automated PASS/FAIL check of AD objects
    ├── 05-verify-shares.ps1     ← FS01: automated PASS/FAIL check of permissions
    └── 06-add-rdp-users.ps1     ← CLIENT01: adds domain users to RDP group
```

## How to run

1. **Create the project folder** (Terraform files in the root, scripts in `scripts/` — `configure-lab.ps1` references `scripts/` by relative path, so this structure must be maintained).
2. **Create the Terraform files** (`backend.tf`, `versions.tf`, `variables.tf`, `main.tf`, `keyvault.tf`, `outputs.tf`, `terraform.tfvars.example`, `.gitignore`).
3. **One-time remote state setup** — run once; if a `RG-TerraformState` storage account already exists, just update `backend.tf` with the existing name:
   ```powershell
   az group create --name RG-TerraformState --location "Central US"
   az storage account create --name <unique-name> --resource-group RG-TerraformState --sku Standard_LRS --encryption-services blob
   az storage container create --name tfstate --account-name <unique-name>
   ```
   Storage account names must be globally unique, 3–24 chars, lowercase letters and numbers only. Then open `backend.tf` and replace `REPLACE_WITH_YOUR_STORAGE_ACCOUNT_NAME` — before running `terraform init`.
4. **Configure variables:**
   ```powershell
   Copy-Item terraform.tfvars.example terraform.tfvars
   # Open terraform.tfvars and set rdp_source to your IP from whatismyip.com
   # Set admin password as environment variable — never put it in a file
   $env:TF_VAR_admin_password = "YourStrongPassword!"
   ```
5. **Deploy infrastructure:**
   ```powershell
   az login
   terraform init    # Downloads providers, connects to remote state
   terraform plan    # Review — expect 12-15 resources including 3 VMs
   terraform apply   # Type yes — takes 10-15 minutes
   terraform output key_vault_name   # Copy it — you pass it to configure-lab.ps1
   ```
6. **Create the scripts** in `scripts/`. These are pushed to VMs automatically by `configure-lab.ps1` — you never run them by hand.
7. **Orchestration script** — `configure-lab.ps1` lives in the project root, not in `scripts/`. It coordinates all seven stages by pushing each script to the right VM through the Azure agent using `az vm run-command`.
8. **Run the lab configuration:**
   ```powershell
   .\configure-lab.ps1 -KeyVaultName "kv-fslab-XXXXXXXX"
   # Takes 15-20 minutes, fully unattended
   ```
9. **Verify** — RDP into CLIENT01 using the public IP from `terraform output` and test each scenario:

   | Log in as | Share | Expected |
   |---|---|---|
   | LAB\sarah.jones | \\FS01\Finance | Read and write |
   | LAB\sarah.jones | \\FS01\HR | Access Denied |
   | LAB\lisa.white | \\FS01\Finance | Read only |
   | LAB\lisa.white | \\FS01\HR | Read and write |
   | LAB\john.smith | \\FS01\IT | Full Control |
   | LAB\tom.davis | \\FS01\Finance | Access Denied |

   `05-verify-ad.ps1` (on DC01) and `05-verify-shares.ps1` (on FS01) print `[PASS]` / `[FAIL]` for each check.
10. **Pause or tear down** — continuing to Lab 2 (RBAC)? Stop the VMs, do not destroy: Lab 2 needs `RG-FileServerLab` and FS01 to exist. Stopped VMs have no compute charges.
    ```powershell
    # Pause — no compute charges while stopped
    az vm stop --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait
    # Restart before Lab 2:
    az vm start --ids $(az vm list -g RG-FileServerLab --query "[].id" -o tsv) --no-wait
    # Full teardown — only when completely done with both labs
    terraform destroy
    ```

## Secrets

- `admin_password` has no default and is marked `sensitive = true`. It must be provided as the `TF_VAR_admin_password` environment variable — **never in a file**.
- `terraform.tfvars` is gitignored. Commit `terraform.tfvars.example` only.
- The admin password is stored in Key Vault as the `vm-admin-password` secret; `configure-lab.ps1` retrieves it at runtime using your logged-in CLI identity.

## Prerequisites

- Terraform >= 1.5.0
- Azure CLI (any recent version)
- PowerShell 5.1+ (built into Windows)

## Troubleshooting

| Problem | Cause | Solution |
|---|---|---|
| configure-lab.ps1 fails at Key Vault | Session expired or missing role | Run `az login`, retry. Confirm Key Vault Secrets User role on the vault. |
| Domain join fails — DNS not resolving | DC01 still finishing promotion | Wait 2 minutes and re-run — configure-lab.ps1 resumes from where it stopped. |
| Cannot RDP to VMs | IP changed or rdp_source mismatch | Run `curl ifconfig.me`, update terraform.tfvars rdp_source, run `terraform apply`. |
| Access Denied unexpected | User not in the right group | Inside RDP run: `whoami /groups` to confirm group membership. |
| GPO not applying | Policy cache not refreshed | Run: `gpupdate /force` inside the VM, then `gpresult /r`. |
| terraform init fails | backend.tf not updated | Open backend.tf, confirm storage account name is correct and container exists. |

## Relationship to other labs

Lab 2 (Azure RBAC) builds directly on top of this lab's infrastructure — three role assignments scoped to FS01 only, no new VMs. It reads Lab 1 resources using data sources and reuses the Lab 1 storage account with a different state key (`rbac-lab.terraform.tfstate`).
