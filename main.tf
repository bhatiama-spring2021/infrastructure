provider "aws" {
  region = var.region
}

variable "region" {
  type = string
}

variable "cidr_block" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "zone_count" {
  type = number
}

variable "subnet_name" {
  type = string
}

variable "second_octet" {
  type    = number
  default = 0
}

# Initialize availability zone data from AWS
data "aws_availability_zones" "available" {}

variable "gateway_name" {
  type = string
}

variable "route_table_name" {
  type = string
}

variable "route_table_cidr_block" {
  type = string
}

variable "ingress_cidr_block" {
  type    = list(any)
  default = ["0.0.0.0/0"]
}

variable "egress_cidr_block" {
  type    = list(any)
  default = ["0.0.0.0/0"]
}

variable "bucket_name" {
  type = string
}

variable "db_name" {
  type = string
}

variable "rds_master_username" {
  type = string
}

variable "rds_master_password" {
  type = string
}

variable "db_subnet_name" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "ami_owners" {
  type = list(any)
}

data "aws_ami" "ami" {
  most_recent = true
  owners      = var.ami_owners
}

variable "ssh_key_name" {
  type = string
}

variable "ec2_name" {
  type = string
}

variable "aws_profile_name" {
  type = string
}

variable "domain_name" {
  type = string
}

data "aws_caller_identity" "current" {}

locals {
  aws_user_account_id = data.aws_caller_identity.current.account_id
}

# VPC
resource "aws_vpc" "vpc" {
  cidr_block                       = var.cidr_block
  enable_dns_hostnames             = true
  enable_dns_support               = true
  enable_classiclink_dns_support   = false
  assign_generated_ipv6_cidr_block = false
  tags = {
    Name = var.vpc_name
  }
}

# Subnets
resource "aws_subnet" "subnet" {
  count                   = var.zone_count
  cidr_block              = "10.${var.second_octet}.${10 + count.index}.0/24"
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = join("", [var.subnet_name, count.index + 1])
  }
}

# Internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = var.gateway_name
  }

}

# Routing table for subnets
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = var.route_table_cidr_block
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
  tags = {
    Name = var.route_table_name
  }
}

# Associate subnets to the route table
resource "aws_route_table_association" "route" {
  count          = var.zone_count
  subnet_id      = element(aws_subnet.subnet.*.id, count.index)
  route_table_id = aws_route_table.route_table.id
}

# Security group for application
resource "aws_security_group" "application_security_group" {
  vpc_id = aws_vpc.vpc.id
  name   = "application_security_group"

  # allow ingress of port 22
  ingress {
    cidr_blocks = var.ingress_cidr_block
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  # allow ingress of port 80
  ingress {
    cidr_blocks = var.ingress_cidr_block
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }

  # allow ingress of port 443
  ingress {
    cidr_blocks = var.ingress_cidr_block
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = var.ingress_cidr_block
    description = "TLS from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"

  }

  # allow egress of all ports
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_block
  }

  tags = {
    Name = "application_sg"
  }
}

# Security group for database
resource "aws_security_group" "database_security_group" {
  name        = "database_security_group"
  description = "Allow MySQL inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"

    security_groups = [
      aws_security_group.application_security_group.id,
    ]
  }

  # allow all outgoing traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_block
  }

  tags = {
    Name = "database_sg"
  }
}

#S3 Bucket
resource "aws_s3_bucket" "s3_bucket" {
  bucket        = var.bucket_name
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "csye6225_s3_bucket"
    Environment = "dev"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    enabled = true

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# Database Subnet Group
resource "aws_db_subnet_group" "db_subnet" {
  name       = var.db_subnet_name
  subnet_ids = aws_subnet.subnet.*.id
}

# RDS Instance
resource "aws_db_instance" "rds_instance" {
  allocated_storage      = "20"
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7.22"
  instance_class         = "db.t3.micro"
  identifier             = var.db_identifier
  name                   = var.db_name
  username               = var.rds_master_username
  password               = var.rds_master_password
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.database_security_group.id]
  storage_encrypted      = true
}

# IAM Role for EC2 Instace
resource "aws_iam_role" "ec2_iam_role" {
  name = "EC2-CSYE6225"

  assume_role_policy = <<-EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow"
        }
      ]
    }
EOF
  tags = {
    Name = "CodeDeployEC2ServiceRole"
  }
}

# Policy for Webapp running on EC2 instance to access s3 bucket
resource "aws_iam_policy" "webapp_s3_policy" {
  name        = "WebAppS3"
  description = "Policy for managing s3"

  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "s3:PutObject",
                "s3:Get*",
                "s3:List*",
                "s3:DeleteObject",
                "s3:DeleteObjectVersion"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::${var.bucket_name}",
                "arn:aws:s3:::${var.bucket_name}/*"
            ]
        }
    ]
}
EOF
}

# Attach webapp policy to EC2 IAM role
resource "aws_iam_role_policy_attachment" "iam_policy_attach" {
  role       = aws_iam_role.ec2_iam_role.name
  policy_arn = aws_iam_policy.webapp_s3_policy.arn
}

# Create Instance Profile for EC2
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_iam_role.name
}

# EC2 Instance
resource "aws_instance" "ec2_instance" {
  ami                         = data.aws_ami.ami.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet[0].id
  vpc_security_group_ids      = aws_security_group.application_security_group.*.id
  key_name                    = var.ssh_key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  user_data                   = <<-EOF
               #!/bin/bash
               sudo echo export "Bucket_Name=${aws_s3_bucket.s3_bucket.bucket}" >> /etc/environment
               sudo echo export "RDS_HOSTNAME=${aws_db_instance.rds_instance.address}" >> /etc/environment
               sudo echo export "DBendpoint=${aws_db_instance.rds_instance.endpoint}" >> /etc/environment
               sudo echo export "RDS_DB_NAME=${aws_db_instance.rds_instance.name}" >> /etc/environment
               sudo echo export "RDS_USERNAME=${aws_db_instance.rds_instance.username}" >> /etc/environment
               sudo echo export "RDS_PASSWORD=${aws_db_instance.rds_instance.password}" >> /etc/environment
               
               EOF

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
  }
  depends_on = [aws_s3_bucket.s3_bucket, aws_db_instance.rds_instance]

  tags = {
    Name = var.ec2_name
  }

}

# Create policy for Codedeploy running on EC2 to access s3 bucket
resource "aws_iam_role_policy" "codeDeploy_ec2_s3" {
  name = "CodeDeploy-EC2-S3"
  role = aws_iam_role.ec2_iam_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:Get*",
        "s3:List*"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::codedeploy.${var.aws_profile_name}.${var.domain_name}/*",
        "arn:aws:s3:::codedeploy.${var.aws_profile_name}.${var.domain_name}/*"
      ]
    }
  ]
}
EOF
}

# Create policy for ghaction user to upload to s3
resource "aws_iam_policy" "gh_upload_to_s3_policy" {
  name   = "GH-Upload-To-S3"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                  "s3:Get*",
                  "s3:List*",
                  "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::codedeploy.${var.aws_profile_name}.${var.domain_name}",
                "arn:aws:s3:::codedeploy.${var.aws_profile_name}.${var.domain_name}/*"
              ]
        }
    ]
}
EOF
}

# Create policy for ghaction user to access codedeploy
resource "aws_iam_policy" "gh_code_deploy_policy" {
  name   = "GH-Code-Deploy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:RegisterApplicationRevision",
        "codedeploy:GetApplicationRevision"
      ],
      "Resource": [
        "arn:aws:codedeploy:${var.region}:${local.aws_user_account_id}:application:${aws_codedeploy_app.code_deploy_app.name}"
      ]

    },
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:CreateDeployment",
        "codedeploy:GetDeployment"
      ],
      "Resource": [
         "arn:aws:codedeploy:${var.region}:${local.aws_user_account_id}:deploymentgroup:${aws_codedeploy_app.code_deploy_app.name}/${aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:GetDeploymentConfig"
      ],
      "Resource": [
        "arn:aws:codedeploy:${var.region}:${local.aws_user_account_id}:deploymentconfig:CodeDeployDefault.OneAtATime",
        "arn:aws:codedeploy:${var.region}:${local.aws_user_account_id}:deploymentconfig:CodeDeployDefault.HalfAtATime",
        "arn:aws:codedeploy:${var.region}:${local.aws_user_account_id}:deploymentconfig:CodeDeployDefault.AllAtOnce"
      ]
    }
  ]
}
EOF
}

# ghaction user policies for packer to work
resource "aws_iam_policy" "gh_ec2_ami_policy" {
  name   = "GH-EC2-AMI-Policy"
  policy = <<-EOF
  {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": [
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CopyImage",
          "ec2:CreateImage",
          "ec2:CreateKeypair",
          "ec2:CreateSecurityGroup",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteKeyPair",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteSnapshot",
          "ec2:DeleteVolume",
          "ec2:DeregisterImage",
          "ec2:DescribeImageAttribute",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeRegions",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSnapshots",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DetachVolume",
          "ec2:GetPasswordData",
          "ec2:ModifyImageAttribute",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifySnapshotAttribute",
          "ec2:RegisterImage",
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances"
        ],
        "Resource" : "*"
      }]
  }
  EOF

}

# Attach policies to ghactions user
resource "aws_iam_user_policy_attachment" "ghactions_ec2_ami_policy_attach" {
  user       = "ghaction"
  policy_arn = aws_iam_policy.gh_ec2_ami_policy.arn
}

resource "aws_iam_user_policy_attachment" "ghactions_s3_policy_attach" {
  user       = "ghaction"
  policy_arn = aws_iam_policy.gh_upload_to_s3_policy.arn
}

resource "aws_iam_user_policy_attachment" "ghactions_codedeploy_policy_attach" {
  user       = "ghaction"
  policy_arn = aws_iam_policy.gh_code_deploy_policy.arn
}

# Create IAM role for codedeploy
resource "aws_iam_role" "code_deploy_role" {
  name = "CodeDeployServiceRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Codedeploy app
resource "aws_codedeploy_app" "code_deploy_app" {
  compute_platform = "Server"
  name             = "csye6225-webapp"
}

# Codedeply group
resource "aws_codedeploy_deployment_group" "code_deploy_deployment_group" {
  app_name               = aws_codedeploy_app.code_deploy_app.name
  deployment_group_name  = "csye6225-webapp-deployment"
  deployment_config_name = "CodeDeployDefault.AllAtOnce"
  service_role_arn       = aws_iam_role.code_deploy_role.arn

  ec2_tag_filter {
    key   = "Name"
    type  = "KEY_AND_VALUE"
    value = var.ec2_name
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }


  depends_on = [aws_codedeploy_app.code_deploy_app]
}

# Attach policy to CodeDeploy role
resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.code_deploy_role.name
}
