// =========================
// VectorFlow CI/CD Pipeline
// =========================
// Main Jenkins pipeline for building, testing, and deploying VectorFlow

pipeline {
    agent any

    environment {
        // Docker Registry
        DOCKER_REGISTRY = credentials('docker-registry-url')
        DOCKER_CREDENTIALS = credentials('docker-registry-credentials')

        // Image tags
        VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'local'}"
        IMAGE_TAG = "${env.BRANCH_NAME == 'main' ? 'latest' : env.BRANCH_NAME}-${VERSION}"

        // Kubernetes
        K8S_NAMESPACE = 'vectorflow'
        KUBECONFIG = credentials('kubeconfig')

        // Slack notifications (optional)
        SLACK_CHANNEL = '#vectorflow-ci'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 60, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()
    }

    stages {
        // ----- Stage 1: Checkout -----
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_MSG = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    env.GIT_AUTHOR = sh(
                        script: 'git log -1 --pretty=%an',
                        returnStdout: true
                    ).trim()
                }
            }
        }

        // ----- Stage 2: Parallel Linting -----
        stage('Lint') {
            parallel {
                stage('Lint Go') {
                    when {
                        changeset 'go/**'
                    }
                    steps {
                        dir('go') {
                            sh 'make lint || true'
                        }
                    }
                }
                stage('Lint Rust') {
                    when {
                        changeset 'rust/**'
                    }
                    steps {
                        dir('rust') {
                            sh 'cargo clippy -- -D warnings || true'
                        }
                    }
                }
                stage('Lint Python') {
                    when {
                        changeset 'python/**'
                    }
                    steps {
                        dir('python') {
                            sh '''
                                python3 -m venv .venv
                                . .venv/bin/activate
                                pip install ruff mypy
                                make lint || true
                            '''
                        }
                    }
                }
                stage('Lint Frontend') {
                    when {
                        changeset 'frontend/**'
                    }
                    steps {
                        dir('frontend') {
                            sh '''
                                npm ci
                                npm run lint || true
                            '''
                        }
                    }
                }
            }
        }

        // ----- Stage 3: Parallel Testing -----
        stage('Test') {
            parallel {
                stage('Test Go') {
                    when {
                        changeset 'go/**'
                    }
                    steps {
                        dir('go') {
                            sh 'make test'
                        }
                    }
                    post {
                        always {
                            junit 'go/test-results.xml'
                        }
                    }
                }
                stage('Test Rust') {
                    when {
                        changeset 'rust/**'
                    }
                    steps {
                        dir('rust') {
                            sh 'cargo test --all'
                        }
                    }
                }
                stage('Test Python') {
                    when {
                        changeset 'python/**'
                    }
                    steps {
                        dir('python') {
                            sh '''
                                python3 -m venv .venv
                                . .venv/bin/activate
                                pip install -r requirements-dev.txt
                                pytest tests/ -v --junitxml=test-results.xml
                            '''
                        }
                    }
                    post {
                        always {
                            junit 'python/test-results.xml'
                        }
                    }
                }
                stage('Test Frontend') {
                    when {
                        changeset 'frontend/**'
                    }
                    steps {
                        dir('frontend') {
                            sh '''
                                npm ci
                                npm test -- --ci --coverage
                            '''
                        }
                    }
                }
            }
        }

        // ----- Stage 4: Build Docker Images -----
        stage('Build Images') {
            parallel {
                stage('Build Gateway') {
                    when {
                        anyOf {
                            changeset 'go/**'
                            branch 'main'
                        }
                    }
                    steps {
                        script {
                            docker.withRegistry("https://${DOCKER_REGISTRY}", 'docker-registry-credentials') {
                                def image = docker.build(
                                    "${DOCKER_REGISTRY}/vectorflow-gateway:${IMAGE_TAG}",
                                    '-f go/Dockerfile go/'
                                )
                                image.push()
                                if (env.BRANCH_NAME == 'main') {
                                    image.push('latest')
                                }
                            }
                        }
                    }
                }
                stage('Build Worker') {
                    when {
                        anyOf {
                            changeset 'rust/**'
                            branch 'main'
                        }
                    }
                    steps {
                        script {
                            docker.withRegistry("https://${DOCKER_REGISTRY}", 'docker-registry-credentials') {
                                def image = docker.build(
                                    "${DOCKER_REGISTRY}/vectorflow-worker:${IMAGE_TAG}",
                                    '-f rust/Dockerfile rust/'
                                )
                                image.push()
                                if (env.BRANCH_NAME == 'main') {
                                    image.push('latest')
                                }
                            }
                        }
                    }
                }
                stage('Build Inference') {
                    when {
                        anyOf {
                            changeset 'python/**'
                            branch 'main'
                        }
                    }
                    steps {
                        script {
                            docker.withRegistry("https://${DOCKER_REGISTRY}", 'docker-registry-credentials') {
                                def image = docker.build(
                                    "${DOCKER_REGISTRY}/vectorflow-inference:${IMAGE_TAG}",
                                    '-f python/Dockerfile python/'
                                )
                                image.push()
                                if (env.BRANCH_NAME == 'main') {
                                    image.push('latest')
                                }
                            }
                        }
                    }
                }
                stage('Build Frontend') {
                    when {
                        anyOf {
                            changeset 'frontend/**'
                            branch 'main'
                        }
                    }
                    steps {
                        script {
                            docker.withRegistry("https://${DOCKER_REGISTRY}", 'docker-registry-credentials') {
                                def image = docker.build(
                                    "${DOCKER_REGISTRY}/vectorflow-frontend:${IMAGE_TAG}",
                                    '-f frontend/Dockerfile frontend/'
                                )
                                image.push()
                                if (env.BRANCH_NAME == 'main') {
                                    image.push('latest')
                                }
                            }
                        }
                    }
                }
            }
        }

        // ----- Stage 5: Security Scan -----
        stage('Security Scan') {
            when {
                branch 'main'
            }
            steps {
                script {
                    // Trivy vulnerability scanning
                    sh """
                        trivy image --severity HIGH,CRITICAL \
                            --exit-code 0 \
                            ${DOCKER_REGISTRY}/vectorflow-inference:${IMAGE_TAG}
                    """
                }
            }
        }

        // ----- Stage 6: Deploy to Staging -----
        stage('Deploy Staging') {
            when {
                branch 'main'
            }
            steps {
                script {
                    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                        sh """
                            # Update image tags
                            cd k8s
                            kustomize edit set image \
                                vectorflow-gateway=${DOCKER_REGISTRY}/vectorflow-gateway:${IMAGE_TAG} \
                                vectorflow-worker=${DOCKER_REGISTRY}/vectorflow-worker:${IMAGE_TAG} \
                                vectorflow-inference=${DOCKER_REGISTRY}/vectorflow-inference:${IMAGE_TAG} \
                                vectorflow-frontend=${DOCKER_REGISTRY}/vectorflow-frontend:${IMAGE_TAG}

                            # Apply to staging namespace
                            kubectl apply -k . -n vectorflow-staging

                            # Wait for rollout
                            kubectl rollout status deployment/vectorflow-gateway -n vectorflow-staging --timeout=300s
                            kubectl rollout status deployment/vectorflow-worker -n vectorflow-staging --timeout=300s
                            kubectl rollout status deployment/vectorflow-inference -n vectorflow-staging --timeout=600s
                            kubectl rollout status deployment/vectorflow-frontend -n vectorflow-staging --timeout=300s
                        """
                    }
                }
            }
        }

        // ----- Stage 7: Integration Tests -----
        stage('Integration Tests') {
            when {
                branch 'main'
            }
            steps {
                sh './jenkins/scripts/smoke-tests.sh staging'
            }
        }

        // ----- Stage 8: Deploy to Production (Manual Approval) -----
        stage('Deploy Production') {
            when {
                branch 'main'
            }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: 'Deploy to Production?', ok: 'Deploy'
                }
                script {
                    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                        sh """
                            cd k8s
                            kubectl apply -k . -n vectorflow

                            # Rolling update with zero downtime
                            kubectl rollout status deployment/vectorflow-gateway -n vectorflow --timeout=300s
                            kubectl rollout status deployment/vectorflow-worker -n vectorflow --timeout=300s
                            kubectl rollout status deployment/vectorflow-inference -n vectorflow --timeout=600s
                            kubectl rollout status deployment/vectorflow-frontend -n vectorflow --timeout=300s
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Pipeline succeeded!"
            // slackSend(channel: env.SLACK_CHANNEL, color: 'good', message: "VectorFlow build #${env.BUILD_NUMBER} succeeded")
        }
        failure {
            echo "Pipeline failed!"
            // slackSend(channel: env.SLACK_CHANNEL, color: 'danger', message: "VectorFlow build #${env.BUILD_NUMBER} failed")
        }
    }
}
