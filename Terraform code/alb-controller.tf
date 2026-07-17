# ==========================================
# Configure "key" for Helm to access EKS
# ==========================================
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.main_eks.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main_eks.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main_eks.name]
      command     = "aws"
    }
  }
}

# 1. Get current cluster information 
data "aws_eks_cluster" "eks_cluster" {
  name = aws_eks_cluster.main_eks.name # <-- REPLACE WITH YOUR CLUSTER NAME HERE
}

# 2. CREATE NEW OIDC Provider for Cluster (Modified to create instead of search)
data "tls_certificate" "eks" {
  url = data.aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc_provider" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

# 3. Create IAM Policy from your latest JSON file
resource "aws_iam_policy" "alb_controller_policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/iam_policy_latest.json")
}

# 4. Create correct Trust Policy for OIDC connection (Fix Permission error)
data "aws_iam_policy_document" "alb_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.oidc_provider.arn]
      type        = "Federated"
    }
  }
}

# 5. Create Role and Attach Policy
resource "aws_iam_role" "alb_controller_role" {
  name               = "AmazonEKSLoadBalancerControllerRole"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "alb_controller_role_attach" {
  role       = aws_iam_role.alb_controller_role.name
  policy_arn = aws_iam_policy.alb_controller_policy.arn
}

# 6. Install AWS Load Balancer Controller via Helm
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  # NEW SYNTAX: Group all environment variables into a list with equal signs
  set = [
    {
      name  = "clusterName"
      value = data.aws_eks_cluster.eks_cluster.name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.alb_controller_role.arn
    },
    # === ONLY ADD THE 2 BLOCKS BELOW ===
    {
      name  = "vpcId"
      value = aws_eks_cluster.main_eks.vpc_config[0].vpc_id
    },
    {
      name  = "region"
      value = "ap-southeast-1"
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.alb_controller_role_attach
  ]
}