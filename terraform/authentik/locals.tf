locals {
  # Club list is generated from the shared data/clubs.yaml (repo root). It is
  # the source of truth for clubs (also drives the nextcloud groupfolders job).
  # Authentik manages a few clubs that are not recorded there yet, so they are
  # unioned explicitly — add them to data/clubs.yaml as they get a quota.
  clubs = sort(distinct(concat(
    [for c in yamldecode(file("${path.module}/../../data/clubs.yaml")) : c.name],
    ["algoets", "applets", "jdgets"],
  )))
}