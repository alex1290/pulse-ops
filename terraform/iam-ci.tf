# Jenkins 推 image 到 ECR 用的 IAM user（最小權限）
# 若 Jenkins 跑在 EC2 上，建議改用 instance profile 而不是 access key
resource "aws_iam_user" "jenkins" {
  name = "${var.project}-jenkins"
}

resource "aws_iam_user_policy" "jenkins_ecr_push" {
  name = "ecr-push"
  user = aws_iam_user.jenkins.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:DescribeImages",
        ]
        Resource = aws_ecr_repository.api.arn
      },
    ]
  })
}
# Access key 請用 AWS Console 或 CLI 手動建立，避免 secret 寫進 Terraform state：
#   aws iam create-access-key --user-name pulse-ops-jenkins
