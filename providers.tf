terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.confluent_tags
  }
}

# resource "random_id" "id" {
#   byte_length = 4
# }
