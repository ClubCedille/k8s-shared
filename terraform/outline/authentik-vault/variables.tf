variable "AUTHENTIK_API_TOKEN" {
  type = string
  sensitive = true
}

variable "db_user" {
  type = string
  sensitive = true
}

variable "db_password" {
  type = string
  sensitive = true
}

variable "b2_id" {
  type = string
  sensitive = true
}

variable "b2_secret" {
  type = string
  sensitive = true
}

variable "dockerhub_secret" {
  type = string
  sensitive = true
}
