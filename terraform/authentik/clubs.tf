module "clubs" {
  source = "./modules/groups"

  for_each = var.clubs
  name     = each.value
}
