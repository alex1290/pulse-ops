module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = "${var.project}-eks"
  cluster_version = var.kubernetes_version

  # 練習用：開放 public endpoint，方便從本機 kubectl 連線
  cluster_endpoint_public_access = true

  # 讓執行 terraform apply 的 IAM 身分成為 cluster admin
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = 1
      max_size       = 3
      desired_size   = var.node_desired_size
    }
  }
}
