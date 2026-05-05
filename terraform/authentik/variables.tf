variable "authentik_token" {
  type = string
}

variable "authentik_url" {
  type = string
}

variable "clubs" {
  type = map(object({}))

  default = {
    cedille            = {}
    conjure            = {}
    chinook            = {}
    capra              = {}
    pontacier          = {}
    raconteursdangle   = {}
    veloom             = {}
    comets             = {}
    lanets             = {}
    synapse            = {}
    musiquets          = {}
    baja               = {}
  }
}
