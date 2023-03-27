
# Recommendation: Overwrite the default in tfvars or stick with the automatic default
variable "tf_last_updated" {
    type = string
    default = ""
    description = "Set this (e.g. in terraform.tfvars) to set the value of the tf_last_updated tag for all resources. If unset, the current date/time is used automatically."
}
# Recommendation: Overwrite the default in tfvars or by specify an environment variable TF_VAR_aws_region
variable "aws_region" {
  type        = string
  default     = "eu-central-1"
  description = "The AWS region to be used"
}

variable "availability_zone" {
  type        = string
  default     = "eu-central-1a"
  description = "The availability zone to be used by default"
}

# Recommendation: Specify this in environment variable TF_VAR_aws_ssh_key_id
variable "aws_ssh_key_id" {
  type        = string
  sensitive   = true
  description = "The ID of the SSH key pair as specified in AWS, used for EC2 instances"
}

variable "purpose" {
  type        = string
  default     = "Testing"
  description = "The purpose of this configuration, used e.g. as tags for AWS resources"
}

variable "username" {
  type        = string
  default     = ""
  description = "Username, used to define local.username if set here. Otherwise, the logged in username is used."
}

variable "owner" {
  type        = string
  default     = ""
  description = "All resources are tagged with an owner tag. If none is provided in this variable, a useful value is derived from the environment"
}

# The validator uses a regular expression for valid email addresses (but NOT complete with respect to RFC 5322)
variable "owner_email" {
  type        = string
  default     = ""
  description = "All resources are tagged with an owner_email tag. If none is provided in this variable, a useful value is derived from the environment"
  validation {
    condition = anytrue([
      var.owner_email == "",
      can(regex("^[a-zA-Z0-9_.+-]+@([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9]+)*\\.)+[a-zA-Z]+$", var.owner_email))
    ])
    error_message = "Please specify a valid email address for variable owner_email or leave it empty"
  }
}

variable "owner_fullname" {
  type        = string
  default     = ""
  description = "All resources are tagged with an owner_fullname tag. If none is provided in this variable, a useful value is derived from the environment"
}

variable "resource_prefix" {
  type        = string
  default     = ""
  description = "This string will be used as prefix for generated resources"
}

variable "instance_type" {
  type        = string
  default     = "t3a.2xlarge"
  description = "Type of the EC2 instance"
}

variable "aws_ami_search" {
  type = map
  default = {
    # Ubuntu
    owner = "099720109477"
    # Ubuntu 22.04
    search = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
  }
  description = "The AMI owner and search string to be used for autoconfiguring the AMI. Once instanciated, fix the AMI ID using aws_ami_id to avoid recreation of your VM!"
}
variable "aws_ami_id" {
  type = string
  default = ""
  description = "AMI to be used for this instance. Leave empty for autoconfiguration. Once found, fix value to avoid recreation of your VM!"
}

# variable "owner_email" {
#     type = string
#     default = var.env.OWNER
# }
