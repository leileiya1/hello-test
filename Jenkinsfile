pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    GIT_REPO = 'git@github.com:leileiya1/hello-test.git'
    GIT_CREDENTIALS = 'jenkins-secret'

    REMOTE_HOST = '10.70.239.17'
    REMOTE_USER = 'sapiece'
    REMOTE_CREDENTIALS = 'ubuntu-server'

    REMOTE_PROJECT_DIR = '/opt/software/sapiece-server/hello'
    REMOTE_ARTIFACT = '/tmp/hello-native.tgz'

    APP_NAME = ''
    APP_VERSION_PREFIX = '0.0'
  }

  stages {
    stage('Checkout') {
      steps {
        deleteDir()
        dir('repo') {
          sshagent(credentials: [env.GIT_CREDENTIALS]) {
            sh '''
              set -euo pipefail
              git clone "$GIT_REPO" .
            '''
          }
        }
      }
    }

    stage('Resolve App Name') {
      steps {
        dir('repo') {
          script {
            def appName = sh(
              script: '''
                set -euo pipefail
                APP_FILE="src/main/resources/application.properties"
                if [ ! -f "$APP_FILE" ]; then
                  echo "application.properties not found: $APP_FILE" >&2
                  exit 1
                fi

                val=$(grep -E '^spring\\.application\\.name=' "$APP_FILE" | tail -n 1 | cut -d'=' -f2- | tr -d '\\r' | xargs || true)
                if [ -z "$val" ]; then
                  echo "spring.application.name is empty or missing" >&2
                  exit 1
                fi

                echo "$val"
              ''',
              returnStdout: true
            ).trim()

            if (!(appName ==~ /^[a-z0-9][a-z0-9._-]*$/)) {
              error("spring.application.name='${appName}' is not valid for Docker image name. Use lowercase letters, numbers, '.', '_' or '-'.")
            }

            env.APP_NAME = appName
            echo "Resolved APP_NAME=${env.APP_NAME}"
          }
        }
      }
    }

    stage('Build Native On Jenkins') {
      steps {
        dir('repo') {
          sh '''
            set -euo pipefail

            if [ -x ./mvnw ]; then
              ./mvnw -Pnative -DskipTests clean native:compile
            else
              mvn -Pnative -DskipTests clean native:compile
            fi

            NATIVE_BIN=$(find target -maxdepth 1 -type f -executable ! -name "*.jar" | head -n 1)
            if [ -z "$NATIVE_BIN" ]; then
              echo "No native executable found under target/."
              ls -lah target || true
              exit 1
            fi

            mkdir -p ../deploy
            cp "$NATIVE_BIN" ../deploy/app
            chmod +x ../deploy/app

            if [ ! -f Dockerfile ]; then
              echo "Dockerfile not found in repository root."
              exit 1
            fi
            cp Dockerfile ../deploy/Dockerfile

            if command -v strip >/dev/null 2>&1; then
              strip ../deploy/app || true
            fi

            tar -C ../deploy -czf ../deploy-native.tgz .

            echo "=== Native Artifact Details (Jenkins) ==="
            ls -lh ../deploy/app ../deploy-native.tgz
            du -h ../deploy/app ../deploy-native.tgz
            file ../deploy/app || true
            sha256sum ../deploy/app ../deploy-native.tgz || true
          '''
        }
      }
    }

    stage('Prepare Remote Directory') {
      steps {
        sshagent(credentials: [env.REMOTE_CREDENTIALS]) {
          sh '''
            set -euo pipefail
            ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
              "mkdir -p '$REMOTE_PROJECT_DIR'"
          '''
        }
      }
    }

    stage('Upload Native Bundle') {
      steps {
        sshagent(credentials: [env.REMOTE_CREDENTIALS]) {
          sh '''
            set -euo pipefail
            scp -o StrictHostKeyChecking=no deploy-native.tgz "$REMOTE_USER@$REMOTE_HOST:$REMOTE_ARTIFACT"
            ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
              "rm -rf '$REMOTE_PROJECT_DIR'/* && tar -xzf '$REMOTE_ARTIFACT' -C '$REMOTE_PROJECT_DIR'"
          '''
        }
      }
    }

    stage('Build Image And Run Container On Remote') {
      steps {
        sshagent(credentials: [env.REMOTE_CREDENTIALS]) {
          sh '''
            set -euo pipefail
            ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
              "REMOTE_PROJECT_DIR='$REMOTE_PROJECT_DIR' APP_NAME='$APP_NAME' APP_VERSION_PREFIX='$APP_VERSION_PREFIX' BUILD_NUMBER='$BUILD_NUMBER' bash -s" <<'EOF'
set -euo pipefail
cd "$REMOTE_PROJECT_DIR"

if docker info >/dev/null 2>&1; then
  USE_SUDO=0
elif sudo -n docker info >/dev/null 2>&1; then
  USE_SUDO=1
else
  echo "Docker is not available for current user, and sudo docker is not permitted."
  exit 1
fi

docker_cmd() {
  if [ "$USE_SUDO" = "1" ]; then
    sudo -n docker "$@"
  else
    docker "$@"
  fi
}

IMAGE_VERSION="${APP_VERSION_PREFIX}.${BUILD_NUMBER}"
IMAGE_TAG="${APP_NAME}:${IMAGE_VERSION}"
LATEST_TAG="${APP_NAME}:latest"
CONTAINER_NAME="${APP_NAME}"

echo "=== Naming ==="
echo "APP_NAME=${APP_NAME}"
echo "IMAGE_VERSION=${IMAGE_VERSION}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "CONTAINER_NAME=${CONTAINER_NAME}"

docker_cmd build --pull --no-cache -t "$IMAGE_TAG" .
docker_cmd tag "$IMAGE_TAG" "$LATEST_TAG"

echo "=== Image Summary ==="
docker_cmd image inspect "$IMAGE_TAG" --format "Image ID: {{.Id}}"
docker_cmd image inspect "$IMAGE_TAG" --format "Image size (bytes): {{.Size}}"
docker_cmd image inspect "$IMAGE_TAG" --format "Virtual size (bytes): {{.VirtualSize}}"
docker_cmd image inspect "$IMAGE_TAG" --format "Created: {{.Created}}"
docker_cmd image inspect "$IMAGE_TAG" --format "Architecture: {{.Architecture}} OS: {{.Os}}"
docker_cmd images "$IMAGE_TAG" --format "Image: {{.Repository}}:{{.Tag}} Size: {{.Size}}"

echo "=== Image Layer History ==="
docker_cmd history "$IMAGE_TAG" --no-trunc

docker_cmd rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker_cmd run -d --name "$CONTAINER_NAME" -p 8080:8080 "$IMAGE_TAG"

echo "=== Container Runtime Info ==="
docker_cmd ps --filter "name=$CONTAINER_NAME" --format "Container: {{.Names}} Status: {{.Status}} Ports: {{.Ports}}"
docker_cmd inspect "$CONTAINER_NAME" --format "StartedAt: {{.State.StartedAt}}"
docker_cmd inspect "$CONTAINER_NAME" --format "RestartCount: {{.RestartCount}}"
docker_cmd logs --tail 50 "$CONTAINER_NAME" || true
docker_cmd stats --no-stream --format "Stats: {{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}} NET={{.NetIO}}" "$CONTAINER_NAME" || true
EOF
          '''
        }
      }
    }
  }

  post {
    always {
      echo "Pipeline finished: ${currentBuild.currentResult}"
    }
  }
}