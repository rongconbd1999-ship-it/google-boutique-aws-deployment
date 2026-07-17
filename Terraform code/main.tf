provider "aws" {
  region = "ap-southeast-1"
}

# 1. Create VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true # Must be enabled for EKS and RDS communication
  enable_dns_support   = true
  tags = { Name = "VPC-DatNguyen-Final-MockProject" }
}

# 2. Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "IGW-DatNguyen" }
}

# 3. Create 2 Public Subnets in 2 different Availability Zones
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "ap-southeast-1a"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1a-Dat" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = "ap-southeast-1b"
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-1b-Dat" }
}

# 4. Create 2 Private Subnets in 2 different Availability Zones
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.20.3.0/24"
  availability_zone = "ap-southeast-1a"
  tags = { Name = "Private-Subnet-1a-Dat" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.20.4.0/24"
  availability_zone = "ap-southeast-1b"
  tags = { Name = "Private-Subnet-1b-Dat" }
}

# 5. Create NAT Gateway (Provide network for private subnets to pull Images)
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id # Place NAT in public subnet
  tags = { Name = "NAT-GW-DatNguyen" }
}

# 6. Create Route Tables
# Public subnets route directly to IGW
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table_association" "pub1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}
resource "aws_route_table_association" "pub2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# Private subnets route to Internet via NAT Gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}
resource "aws_route_table_association" "priv1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "priv2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}