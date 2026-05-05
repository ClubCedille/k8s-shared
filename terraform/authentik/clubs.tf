variable "clubs" {
  type = set(string)
  default = [
    "cedille",
    "conjure",
    "chinook",
    "capra",
    "pontacier",
    "raconteursdangle",
    "veloom",
    "comets",
    "lanets",
    "synapse",
    "musiquets",
    "baja",
  ]
}

module "clubs" {
  source = "./modules/groups"

  for_each = var.clubs
  name     = each.value
}
