# ==========================================
# 1. GRANT PERMISSIONS (IAM ROLE) FOR MASTER NODE
# ==========================================
resource "aws_iam_role" "eks_master_role" {
  name = "eks-master-role-dat"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_master_role.name
}

# ==========================================
# 2. CREATE EKS CLUSTER (MASTER NODE)
# ==========================================
resource "aws_eks_cluster" "main_eks" {
  name     = "EKS-Cluster-DatNguyen"
  role_arn = aws_iam_role.eks_master_role.arn

  vpc_config {
    # Force Master Node to connect to 2 Private subnets
    subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  }
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# ==========================================
# 3. GRANT PERMISSIONS (IAM ROLE) FOR WORKER NODES
# ==========================================
resource "aws_iam_role" "eks_worker_role" {
  name = "eks-worker-role-dat"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_worker_role.name
}
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_worker_role.name
}
resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_worker_role.name
}

# ==========================================
# 4. CREATE WORKER NODES
# ==========================================
resource "aws_eks_node_group" "worker_nodes" {
  cluster_name    = aws_eks_cluster.main_eks.name
  node_group_name = "worker-group-datnguyen"
  node_role_arn   = aws_iam_role.eks_worker_role.arn
  # Place Worker nodes in Private subnets
  subnet_ids      = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 10  # Desired number of instances
    max_size     = 10  # Maximum number of instances
    min_size     = 10  # Minimum number of instances
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]
}