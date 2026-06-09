variable "admin_username" {
  description = "Local admin username for all VMs"
  type        = string
  default     = "demoadmin"
}

variable "admin_password" {
  description = "Local admin password for all VMs (min 12 chars, must include upper, lower, digit, special)"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Active Directory fully qualified domain name"
  type        = string
  default     = "demo.local"
}

variable "domain_netbios" {
  description = "Active Directory NetBIOS domain name"
  type        = string
  default     = "DEMO"
}

variable "safe_mode_password" {
  description = "DSRM (Directory Services Restore Mode) password"
  type        = string
  sensitive   = true
}

variable "vpn_shared_key" {
  description = "Pre-shared key for the S2S VPN connection"
  type        = string
  sensitive   = true
  default     = "Demo@VPN$haredKey2024!"
}

variable "domain_admin_password" {
  description = "Password for the demo-admin domain user"
  type        = string
  sensitive   = true
}

variable "domain_user_password" {
  description = "Password for the demo-user domain user"
  type        = string
  sensitive   = true
}
