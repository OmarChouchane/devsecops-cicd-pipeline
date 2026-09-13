pipeline {
  agent {
    docker {
      image 'maven:3.9.9-eclipse-temurin-17'
      args '--user root -v /var/run/docker.sock:/var/run/docker.sock -v /usr/bin/docker:/usr/bin/docker --add-host=host.docker.internal:host-gateway' // mount Docker socket to access the host's Docker daemon
    }
  }
  options {
    skipDefaultCheckout(true)
  }
  environment {
    DOCKER_IMAGE = "omarchouchane/ultimate-cicd:${BUILD_NUMBER}"
    VAULT_ADDR   = "http://host.docker.internal:8200"
    VAULT_VERSION = "1.17.2"
  }
  stages {
    stage('Checkout') {
      steps {
        sh 'docker run --rm -u root -v "$WORKSPACE":/workspace alpine sh -lc "rm -rf /workspace/* /workspace/.[!.]* /workspace/..?* /workspace/.??* 2>/dev/null || true"'
        checkout scm
      }
    }
    stage('Fetch Dynamic Secrets from Vault') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'vault-approle', usernameVariable: 'VAULT_ROLE_ID', passwordVariable: 'VAULT_SECRET_ID')]) {
          script {
            sh '''
              docker rm -f vault-cli-extract >/dev/null 2>&1 || true
              docker create --name vault-cli-extract hashicorp/vault:${VAULT_VERSION}
              docker cp vault-cli-extract:/bin/vault /usr/local/bin/vault
              docker rm vault-cli-extract
              chmod +x /usr/local/bin/vault
            '''
            // Short-lived token issued per build via AppRole login (not a long-lived static secret)
            env.VAULT_TOKEN = sh(script: 'vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID"', returnStdout: true).trim()
            env.SONAR_TOKEN    = sh(script: 'vault kv get -field=token secret/sonarqube', returnStdout: true).trim()
            env.DOCKERHUB_USER = sh(script: 'vault kv get -field=username secret/dockerhub', returnStdout: true).trim()
            env.DOCKERHUB_PASS = sh(script: 'vault kv get -field=password secret/dockerhub', returnStdout: true).trim()
            env.GITHUB_TOKEN   = sh(script: 'vault kv get -field=token secret/github', returnStdout: true).trim()
          }
        }
      }
    }
    stage('Build and Test') {
      steps {
        sh 'mvn clean package'
      }
    }
    stage('Static Code Analysis') {
      environment {
        SONAR_URL = "http://host.docker.internal:9000"
      }
      steps {
        sh 'mvn org.sonarsource.scanner.maven:sonar-maven-plugin:4.0.0.4121:sonar -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=${SONAR_URL} -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=300'
      }
    }
    stage('Trivy Filesystem Scan') {
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE":/workspace aquasec/trivy:latest fs \
            --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed /workspace
        '''
      }
    }
    stage('Build Docker Image') {
      steps {
        sh 'docker build -t ${DOCKER_IMAGE} .'
      }
    }
    stage('Trivy Image Scan') {
      steps {
        sh '''
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image \
            --exit-code 1 --severity CRITICAL --ignore-unfixed ${DOCKER_IMAGE}
        '''
      }
    }
    stage('Push Docker Image') {
      steps {
        sh '''
          echo "$DOCKERHUB_PASS" | docker login -u "$DOCKERHUB_USER" --password-stdin
          docker push ${DOCKER_IMAGE}
        '''
      }
    }
    stage('Generate SBOM (Syft)') {
      steps {
        sh '''
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$WORKSPACE":/output \
            anchore/syft:latest ${DOCKER_IMAGE} -o cyclonedx-json=/output/sbom-${BUILD_NUMBER}.json
        '''
        archiveArtifacts artifacts: "sbom-${BUILD_NUMBER}.json", fingerprint: true
      }
    }
    stage('SBOM Vulnerability Scan (Grype)') {
      steps {
        sh '''
          docker run --rm \
            -v "$WORKSPACE":/input \
            anchore/grype:latest sbom:/input/sbom-${BUILD_NUMBER}.json --fail-on critical -o table
        '''
      }
    }
    stage('Sign Image (Cosign via Vault Transit)') {
      steps {
        sh '''
          curl -sSfL -o /usr/local/bin/cosign https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
          chmod +x /usr/local/bin/cosign
          cosign sign --key hashivault://cosign-key --yes ${DOCKER_IMAGE}
        '''
      }
    }
    stage('Update Deployment File') {
        environment {
        GIT_REPO_NAME = "spring-app-manifests"
        GIT_USER_NAME = "omarchouchane"
        }
        steps {
                sh '''
          git config --global user.email "omar.ch52831@gmail.com"
          git config --global user.name "Omar Chouchane"
                    BUILD_NUMBER=${BUILD_NUMBER}
            rm -rf spring-app-manifests
            git clone https://${GITHUB_TOKEN}@github.com/${GIT_USER_NAME}/${GIT_REPO_NAME}.git
          cd spring-app-manifests
          DEPLOY_FILE=$(find . -maxdepth 2 -type f -name 'deployment.yaml' | head -n 1)
          if [ -z "$DEPLOY_FILE" ]; then DEPLOY_FILE=$(find . -maxdepth 2 -type f -name 'deployment.yml' | head -n 1); fi
          if [ -z "$DEPLOY_FILE" ]; then echo "Deployment file not found"; exit 1; fi
          sed -i "s|image: .*|image: omarchouchane/ultimate-cicd:${BUILD_NUMBER}|g" "$DEPLOY_FILE"
          git add "$DEPLOY_FILE"
                    git commit -m "Update deployment image to version ${BUILD_NUMBER}"
            git push https://${GITHUB_TOKEN}@github.com/${GIT_USER_NAME}/${GIT_REPO_NAME}.git HEAD:main
                '''
        }
    }
  }
  post {
    always {
      script {
        if (env.VAULT_TOKEN) {
          sh 'vault token revoke "$VAULT_TOKEN" || true'
        }
      }
    }
  }
}
