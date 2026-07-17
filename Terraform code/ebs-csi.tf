# ==========================================
# ADDITIONAL CONFIGURATION: AMAZON EBS CSI DRIVER
# (Helps Kubernetes automatically create and attach EBS volumes to Pods)
# ==========================================

# 1. Create Trust Policy (Reuse OIDC Provider from alb-controller.tf)
data "aws_iam_policy_document" "ebs_csi_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      # Get URL variable from the previously created OIDC Provider
      variable = "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
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

# 2. Create IAM Role for EBS CSI Driver
resource "aws_iam_role" "ebs_csi_role" {
  name               = "AmazonEKS_EBS_CSI_DriverRole_DatNguyen"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role_policy.json
}

# 3. Attach existing AWS Policy (AmazonEBSCSIDriverPolicy) to Role
resource "aws_iam_role_policy_attachment" "ebs_csi_role_attach" {
  role       = aws_iam_role.ebs_csi_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# 4. Install EBS CSI Driver Add-on directly into EKS cluster
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main_eks.name
  addon_name               = "aws-ebs-csi-driver"
  # Leave addon_version empty so AWS automatically chooses the most compatible version for your EKS
  service_account_role_arn = aws_iam_role.ebs_csi_role.arn

  # Ensure Role is created before installing Add-on
  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_role_attach
  ]
}