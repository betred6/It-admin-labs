# Terraform AD Domain Controller Lab

Deploy a Windows Server 2022 VM on Azure with Terraform and auto-promote it to an Active Directory domain controller via a Custom Script Extension. New forest `corp.betre.com` (NetBIOS `CORP`), admin user `adadmin`.

This is Jhante's admin-classroom lab, separate from the NTFS / RBAC / AUM series. It is also the Terraform deployment behind the "Using Terraform To Deploy Your Lab Environment" Skool lesson.

## What it builds

- Resource group `rg-ad-betre`
- VNet `10.0.0.0/16`, subnet `10.0.1.0/24`
- Static Standard public IP
- NSG with RDP (TCP 3389) allowed
- NIC with static private IP `10.0.1.4`
- VM `vm-ad-betre` (computer name `ad-betre`), Standard_D2s_v3, Premium_LRS 127 GB, Windows Server 2022 Datacenter
- Custom Script Extension `install-ad-ds` runs `Install-ADDSForest`

## How to run

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and replace the two password placeholders with two strong, different passwords you choose. Never send them to anyone, never screenshot the file, never commit it.
2. `terraform init`
3. `terraform plan` — read it before applying.
4. `terraform apply` — creates the VM. Apply takes ~5–8 min, the extension another ~3–5 min, then the VM auto-reboots. Wait 5–10 min before RDP.
5. RDP as `CORP\adadmin` (or `adadmin@corp.betre.com`) to the public IP from `terraform output public_ip`. Never post the public IP.
6. Verify on the VM:
   - `Get-Service NTDS`
   - `Get-ADDomain`
   - `Get-ADDomainController -Filter *`
   - `Resolve-DnsName corp.betre.com`
7. When done: `terraform destroy`. Do not leave the VM running.

## Flags

- **Cost:** ~$0.20/hour while the VM runs — over $100/month if left on. Destroy when done.
- **RDP is open to the whole internet** (`source_address_prefix = "*"`). Restrict it to your own IP before applying if you can.
- **Passwords are in plaintext** in `terraform.tfvars` and in the AutoLogon unattend content. Use strong, unique passwords and never commit `terraform.tfvars`, `*.tfstate`, or `.terraform/` (see `.gitignore`).

## Status

Files rebuilt Nov 20, 2026 after the local `az-ad-vm` folder was deleted; the Terraform code is the lab doc's code with yourname set to `betre` and the domain set to `corp.betre.com`. Deployment was still pending at rebuild time — due Fri Nov 20, 2026, 6:59 PM ET.
