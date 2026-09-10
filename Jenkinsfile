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
  }
  stages {
    stage('Checkout') {
      steps {
        sh 'docker run --rm -u root -v "$WORKSPACE":/workspace alpine sh -lc "rm -rf /workspace/* /workspace/.[!.]* /workspace/..?* /workspace/.??* 2>/dev/null || true"'
        checkout scm
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
        withCredentials([string(credentialsId: 'sonarqube', variable: 'SONAR_TOKEN')]) {
          sh 'mvn org.sonarsource.scanner.maven:sonar-maven-plugin:4.0.0.4121:sonar -Dsonar.token=$SONAR_TOKEN -Dsonar.host.url=${SONAR_URL} -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=300'
        }
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
      environment {
        REGISTRY_CREDENTIALS = credentials('docker-cred')
      }
      steps {
        script {
          def dockerImage = docker.image("${DOCKER_IMAGE}")
          docker.withRegistry('https://index.docker.io/v1/', "docker-cred") {
              dockerImage.push()
          }
        }
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
    stage('Update Deployment File') {
        environment {
        GIT_REPO_NAME = "spring-app-manifests"
        GIT_USER_NAME = "omarchouchane"
        }
        steps {
            withCredentials([string(credentialsId: 'github', variable: 'GITHUB_TOKEN')]) {
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
  }
}
