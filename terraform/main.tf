terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ---------------------------------------------------------
# 1. REDES (VPC CUSTOM Y SUBREDES PROPIAS)
# ---------------------------------------------------------
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "duoc-vpc-proyecto"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "duoc-igw"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                                         = "duoc-public-1"
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/duoc-eks-cluster-cli" = "shared"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name                                         = "duoc-public-2"
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/duoc-eks-cluster-cli" = "shared"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "duoc-public-rt"
  }
}

resource "aws_route_table_association" "a1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "a2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# ---------------------------------------------------------
# 2. IDENTIDAD (USAR ROL EXISTENTE DEL LABORATORIO)
# ---------------------------------------------------------
# IMPORTANTE: Cambia "LabRole" si en tu consola de IAM se llama distinto
data "aws_iam_role" "lab_role" {
  name = "LabRole" 
}

# ---------------------------------------------------------
# 3. CLÚSTER EKS
# ---------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = "duoc-eks-cluster-cli"
  role_arn = data.aws_iam_role.lab_role.arn # Usamos el ARN del rol preexistente

  vpc_config {
    subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  }
}

# ---------------------------------------------------------
# 4. GRUPO DE NODOS
# ---------------------------------------------------------
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "duoc-workers-custom"
  node_role_arn   = data.aws_iam_role.lab_role.arn # Los nodos usan el mismo rol preexistente
  subnet_ids      = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  # Como no creamos attachments condicionales, dependemos directamente del clúster
  depends_on = [aws_eks_cluster.main]
}