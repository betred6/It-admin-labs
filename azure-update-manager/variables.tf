variable "location"            { type=string  default="eastus" }
variable "resource_group_name" { type=string  default="rg-aumlab" }
variable "admin_username"      { type=string  default="labadmin" }
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Set as TF_VAR_admin_password env var — never in a file. Min 12 chars, upper+lower+number+symbol."
}
variable "dsrm_password" {
  type        = string
  sensitive   = true
  description = "Set as TF_VAR_dsrm_password env var — never in a file. Used by the DC01 promotion extension as the Directory Services Restore Mode password."
}
variable "allowed_rdp_ip" {
  type        = string
  description = "Your public IP in CIDR format — e.g. 1.2.3.4/32. Find at whatismyip.com"
}
variable "domain_name"    { type=string  default="aumlab.local" }
variable "domain_netbios" { type=string  default="AUMLAB" }
