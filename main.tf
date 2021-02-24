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
  type = number
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

# VPC
resource "aws_vpc" "vpc" {
  cidr_block                       = var.cidr_block
  enable_dns_hostnames             = true
  enable_dns_support               = true
  enable_classiclink_dns_support   = true
  assign_generated_ipv6_cidr_block = false
  tags = {
    Name = var.vpc_name
  }
}

# Subnets
resource "aws_subnet" "subnet" {
  count = var.zone_count
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
