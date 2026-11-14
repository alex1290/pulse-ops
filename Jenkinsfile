// 需要的 Jenkins 設定：
//   - Plugins: Pipeline, Git, Credentials Binding, AWS Credentials
//   - Agent 上需安裝：docker, aws cli, git
//   - Credentials:
//       aws-ecr-push  (AWS Credentials)       → Terraform 建立的 pulse-ops-jenkins user
//       github-token  (Username with password) → 可 push pulse-ops-manifests 的 GitHub PAT

pipeline {
  agent any

  environment {
    AWS_REGION     = 'ap-northeast-1'
    AWS_ACCOUNT_ID = '<YOUR_AWS_ACCOUNT_ID>'
    ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    IMAGE_NAME     = 'pulse-api'
    MANIFESTS_REPO = 'github.com/<your-github>/pulse-ops-manifests.git'
    OVERLAY_PATH   = 'overlays/dev'
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  stages {
    stage('Init') {
      steps {
        script {
          env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          env.IMAGE_URI = "${env.ECR_REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
        }
        echo "Image: ${env.IMAGE_URI}"
      }
    }

    stage('Test') {
      steps {
        sh '''
          docker run --rm -v "$PWD/app":/app -w /app node:24-alpine \
            sh -c "npm ci && npm test"
        '''
      }
    }

    stage('Build') {
      steps {
        sh '''
          docker build \
            -f docker/Dockerfile \
            --build-arg APP_VERSION=${IMAGE_TAG} \
            -t ${IMAGE_URI} \
            ./app
        '''
      }
    }

    stage('Push to ECR') {
      when { branch 'main' }
      steps {
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-ecr-push']]) {
          sh '''
            aws ecr get-login-password --region ${AWS_REGION} \
              | docker login --username AWS --password-stdin ${ECR_REGISTRY}
            docker push ${IMAGE_URI}
          '''
        }
      }
    }

    // GitOps 關鍵：更新 manifests repo 的 image tag，ArgoCD 偵測到 commit 後自動部署
    stage('Update GitOps manifests') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github-token',
                                          usernameVariable: 'GIT_USER',
                                          passwordVariable: 'GIT_TOKEN')]) {
          sh '''
            rm -rf manifests
            git clone https://${GIT_USER}:${GIT_TOKEN}@${MANIFESTS_REPO} manifests
            cd manifests
            sed -i "s|newTag: .*|newTag: \\"${IMAGE_TAG}\\"|" ${OVERLAY_PATH}/kustomization.yaml
            git config user.name  "jenkins"
            git config user.email "jenkins@pulse-ops.local"
            git add ${OVERLAY_PATH}/kustomization.yaml
            git diff --cached --quiet && echo "No changes" && exit 0
            git commit -m "ci: deploy pulse-api ${IMAGE_TAG}"
            git push origin HEAD:main
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'docker image rm ${IMAGE_URI} || true'
    }
  }
}
