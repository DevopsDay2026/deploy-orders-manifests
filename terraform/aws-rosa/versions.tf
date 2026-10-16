terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.51.0"
    }
    rhcs = {
      source  = "terraform-redhat/rhcs"
      version = ">= 1.7.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
