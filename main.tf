# Note: VPC and related resources are imported from the remote S3 terraform store

# Import existing: terraform import aws_security_group.sg_dualstack <AWS Resource ID>
resource "aws_security_group" "sg_ec2_instance" {
  name        = "${local.resource_prefix}-${var.instance_name}"
  description = "Allow only SSH"
  vpc_id      = data.terraform_remote_state.common_vpc.outputs.vpc_dualstack.id

  # Generate dualstack ingress for for the following tcp ports: 22 (ssh), 80 (http), 443 (https)
  # Alternatively, only for port 22
  dynamic "ingress" {
    #for_each = { 1 : 22, 2 : 80, 3 : 443 }
    for_each = { 1 : 22 }
    content {
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      from_port        = ingress.value
      to_port          = ingress.value
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
data "aws_ami" "autoconfigured_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.aws_ami_search.search]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.aws_ami_search.owner] # Canonical
}

data "cloudinit_config" "ec2_instance_init" {
  gzip          = false
  base64_encode = false
  part {
    #filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"
    content  = <<-EOF
        #cloud-config
        # See documentation for more configuration examples
        # https://cloudinit.readthedocs.io/en/latest/reference/examples.html 

        # Install arbitrary packages
        # https://cloudinit.readthedocs.io/en/latest/reference/examples.html#install-arbitrary-packages
        apt:
            preserve_sources_list: true
            sources:
                confluent-clients:
                    source: "deb https://packages.confluent.io/clients/deb focal main"
                    # Confluent key ID extraced by running wget -qO - https://packages.confluent.io/deb/7.4/archive.key | gpg --with-fingerprint --with-colons | awk -F: '/^fpr/ { print $10 }'
                    keyid: CBBB821E8FAF364F79835C438B1DA6120C2BF624
                    # Install by adding "confluent-kafka" or "confluent-server" to list of apt packages
                confluent-platform-7-4:
                    source: "deb [arch=amd64] https://packages.confluent.io/deb/7.4 stable main"
                    # Confluent key ID extraced by running wget -qO - https://packages.confluent.io/deb/7.4/archive.key | gpg --with-fingerprint --with-colons | awk -F: '/^fpr/ { print $10 }'
                    keyid: CBBB821E8FAF364F79835C438B1DA6120C2BF624
                    # Install by adding "confluent-platform" to list of apt packages
        package_update: true
        package_upgrade: true
        packages: ${local.apt_package_list}
        #write_files:
        #- path: <filename>
        #  content: |
        #        <file content>
        #        <file content2>
        # Run commands on first boot
        # https://cloudinit.readthedocs.io/en/latest/reference/examples.html#run-commands-on-first-boot
        runcmd:
        - sudo snap refresh
        - sudo apt-file update
        - if [ \! -z "${var.instance_initial_snap_packages}" ]; then sudo snap install ${var.instance_initial_snap_packages}; fi
        - if [ \! -z "${var.instance_initial_classic_snap_packages}" ]; then sudo snap install --classic ${var.instance_initial_snap_packages}; fi
    EOF
  }
}


resource "aws_instance" "ec2_instance" {
  ami           = var.aws_ami_id!="" ? var.aws_ami_id : data.aws_ami.autoconfigured_ami.id
  instance_type = var.instance_type
  # Use subnet from common vpc, availability zone a1
  subnet_id                   = data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1b.id
  associate_public_ip_address = true
  # Use availability zone of the chosen subnets
  availability_zone = data.terraform_remote_state.common_vpc.outputs.subnet_dualstack_1b.availability_zone
  key_name          = data.terraform_remote_state.common_vpc.outputs.ssh_key_default.key_name
  hibernation       = true

  vpc_security_group_ids = [
    aws_security_group.sg_ec2_instance.id
  ]
  root_block_device {
    delete_on_termination = true
    volume_size           = 150
    volume_type           = "gp3"
    tags                  = local.confluent_tags
    encrypted             = true
  }

  user_data = data.cloudinit_config.ec2_instance_init.rendered
  /* user_data = <<-EOF
    #!/bin/bash
    sudo apt-get upgrade && sudo apt-get dist-upgrade -y
    snap refresh
    if [ \! -z "${var.instance_initial_apt_packages}" ]; then 
      apt-get install -y ${var.instance_initial_apt_packages}
    fi
    if [ \! -z "${var.instance_initial_snap_packages}" ]; then
      snap install ${var.instance_initial_snap_packages}
    fi
    if [ \! -z "${var.instance_initial_classic_snap_packages}" ]; then
      snap install --classic ${var.instance_initial_snap_packages}
    fi
  EOF */
  tags = {
    Name = "${local.resource_prefix}-${var.instance_name}"
  }

  # depends_on = [ aws_security_group.project-iac-sg ]
}

# Use CloudWatch to detect inactivity and shut down the instance after a while
resource "aws_cloudwatch_metric_alarm" "alarm_instance_idle_shutdown" {
  alarm_name          = "alarm-${aws_instance.ec2_instance.tags["Name"]}-idle"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 12
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.5"
  alarm_description = "Stop the EC2 instance when CPU utilization stays below 10% on average for 12 periods of 5 minutes, i.e. 1 hour"
  actions_enabled           = true
  alarm_actions             = ["arn:aws:automate:${var.aws_region}:ec2:stop"]
  treat_missing_data        = "notBreaching"

  dimensions = {
    InstanceId = "${aws_instance.ec2_instance.id}"
  }

}

resource "aws_route53_record" "ec2_instance_dns_cname" {
  zone_id = data.terraform_remote_state.common_vpc.outputs.private_hostedzone_vpc.zone_id
  name    = "${local.resource_prefix}-${var.instance_name}.${data.terraform_remote_state.common_vpc.outputs.private_hostedzone_vpc.name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_instance.ec2_instance.private_dns]
}
resource "aws_route53_record" "ec2_instance_public_dns_cname" {
  # Only use this if all required data has been provided by the user
  count = (var.dns_suffix!="" && var.dns_zone_id!="") ? 1 : 0
  zone_id = var.dns_zone_id
  name    = "${var.instance_name}.${local.confluent_tags.owner}.${var.dns_suffix}"
  type    = "AAAA"
  ttl     = 300
  records = [aws_instance.ec2_instance.ipv6_addresses[0]]
}

# output "common_vpc" {
#   value = data.terraform_remote_state.outputs.common_vpc
# }

output "ec2_instance_private_dns_name" {
  value = aws_route53_record.ec2_instance_dns_cname.name
}
