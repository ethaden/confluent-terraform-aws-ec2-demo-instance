# Note: VPC and related resources are imported from the remote S3 terraform store

# Import existing: terraform import aws_security_group.sg_dualstack <AWS Resource ID>
resource "aws_security_group" "sg_dualstack_demo_instance" {
  name        = "${local.resource_prefix}-demo"
  description = "Allow only SSH"
  vpc_id      = data.terraform_remote_state.common_vpc.outputs.vpc_dualstack.id

  # Generate dualstack ingress for for the following tcp ports: 22 (ssh), 80 (http), 443 (https)
  dynamic "ingress" {
    for_each = {1: 22, 2: 80, 3: 443}
    content {
      protocol = "tcp"
      cidr_blocks      = [data.terraform_remote_state.common_vpc.outputs.vpc_dualstack.cidr_block]
      ipv6_cidr_blocks = [data.terraform_remote_state.common_vpc.outputs.vpc_dualstack.ipv6_cidr_block]
      from_port  = ingress.value
      to_port    = ingress.value
    }
  }

  ingress {
    description      = "Allow everything"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [data.terraform_remote_state.common_vpc.outputs.vpc_dualstack.cidr_block]
    ipv6_cidr_blocks = [data.terraform_remote_state.common_vpc.outputs.vpc_dualstack.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

#   tags = {
#     Name = "allow_tls"
#   }
  lifecycle {
    prevent_destroy = false
  }
}

# Lookup AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "ec2_instance" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  # Use subnet from common vpc, availability zone a1
  subnet_id =  data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1a.id
  associate_public_ip_address = true
  # Use availability zone of the chosen subnets
  availability_zone = data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1a.availability_zone
  key_name = data.terraform_remote_state.common_vpc.outputs.ssh_key_default.key_name
  hibernation = true

  # vpc_security_group_ids = [
  #   aws_security_group.sg_dualstack_demo_instance.id
  # ]
  root_block_device {
    delete_on_termination = true
    volume_size = 150
    volume_type = "gp3"
    tags = local.confluent_tags
    encrypted = true
  }
  tags = {
    Name = "${local.resource_prefix}-demo"
  }

  # depends_on = [ aws_security_group.project-iac-sg ]
}

resource "aws_route53_record" "ec2_instance_dns_cname" {
  zone_id = data.terraform_remote_state.common_vpc.outputs.private_hostedzone_vpc.zone_id
  name    = "${local.resource_prefix}-demo.${data.terraform_remote_state.common_vpc.outputs.private_hostedzone_vpc.name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_instance.ec2_instance.private_dns]
}


# output "common_vpc" {
#   value = data.terraform_remote_state.outputs.common_vpc
# }

output "ec2_instance_private_dns_name" {
  value = aws_route53_record.ec2_instance_dns_cname.name
}
