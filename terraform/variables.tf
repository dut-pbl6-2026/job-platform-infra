variable "subscription_id" {
  description = "Azure subscription ID (one per student account). Never commit real values: put it in envs/<name>.tfvars (gitignored)."
  type        = string
}

variable "prefix" {
  description = "Name prefix for all resources."
  type        = string
  default     = "jobplatform"
}

variable "location" {
  description = "Azure region. Azure for Students restricts regions/SKUs: check `az vm list-skus -l <region> --size Standard_B2 --resource-type virtualMachines`."
  type        = string
  default     = "southeastasia"
}

variable "vm_size" {
  description = "VM size (2 vCPU / 8 GB by default)."
  type        = string
  default     = "Standard_B2ms"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB (StandardSSD_LRS)."
  type        = number
  default     = 64
}

variable "admin_username" {
  description = "Linux admin user."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key contents (e.g. output of `cat ~/.ssh/id_ed25519.pub`)."
  type        = string

  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) ", var.ssh_public_key)) || can(regex("^ecdsa-sha2-", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key."
  }
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH (port 22), e.g. 203.0.113.7/32. Use your own IP; avoid 0.0.0.0/0."
  type        = string
}

variable "dns_label" {
  description = "Public DNS label -> <label>.<location>.cloudapp.azure.com. Must be globally unique per region; empty = <prefix>-<random>."
  type        = string
  default     = ""
}

variable "open_gateway_port" {
  description = "Open the gateway port to the internet (disable when a TLS reverse proxy fronts it)."
  type        = bool
  default     = true
}

variable "gateway_port" {
  description = "Gateway host port (GATEWAY_PORT in docker-compose.prod.yml)."
  type        = number
  default     = 5000
}

variable "auto_shutdown_time" {
  description = "Daily auto-deallocate time, HHMM in auto_shutdown_timezone (cost safety net). 1500 UTC = 22:00 Vietnam."
  type        = string
  default     = "1500"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "auto_shutdown_time must be HHMM (e.g. 1500)."
  }
}

variable "auto_shutdown_timezone" {
  description = "Windows time zone name for the schedule."
  type        = string
  default     = "UTC"
}

variable "auto_shutdown_enabled" {
  description = "Enable the nightly auto-shutdown schedule."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
