# Vendored from ClubCedille/cedille-workflows (.tflint.hcl) so pre-commit runs
# the exact same ruleset as the terraform-lint CI job.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
