pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out source code'
                checkout scm
            }
        }

        stage('Secret Scanning') {
            steps {
                echo 'Scanning repository for exposed secrets'
                sh '''
                    trufflehog --no-update git file://. --fail
                '''
            }
        }

        stage('Retrieve Application Secrets') {
            steps {
                script {
                    def secret = sh(
                        script: '''
                            aws secretsmanager get-secret-value \
                            --secret-id telecom-cicd/app \
                            --region us-east-1 \
                            --query SecretString \
                            --output text
                        ''',
                        returnStdout: true
                    ).trim()

                    def credentials = readJSON text: secret

                    env.DB_USERNAME = credentials.DB_USERNAME
                    env.DB_PASSWORD = credentials.DB_PASSWORD
                    env.BILLING_API_KEY = credentials.BILLING_API_KEY
                }
            }
        }

        stage('Build') {
            steps {
                echo 'Build stage will be configured in Step 3'
            }
        }

        stage('Unit Test') {
            steps {
                echo 'Unit tests will be configured in Step 3'
            }
        }

        stage('SonarQube Scan') {
            steps {
                echo 'SonarQube will be configured in Step 3'
            }
        }

        
        stage('Docker Build & Push') {
            steps {
                script {
                    env.AWS_REGION = 'us-east-1'
                    env.ECR_REPOSITORY = 'telecom-cicd-pipeline'

                    env.AWS_ACCOUNT_ID = sh(
                        script: 'aws sts get-caller-identity --query Account --output text',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = env.BUILD_NUMBER

                    env.IMAGE_URI = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"

                    sh '''
                        set -eu

                        echo "Checking Dockerfile..."

                        test -f Dockerfile

                        echo "Authenticating with Amazon ECR..."

                        aws ecr get-login-password \
                            --region "$AWS_REGION" \
                            | docker login \
                            --username AWS \
                            --password-stdin \
                            "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

                        echo "Building Docker image..."

                        docker build -t "$IMAGE_URI" .

                        echo "Pushing image to Amazon ECR..."

                        docker push "$IMAGE_URI"

                        echo "Docker image successfully pushed."
                    '''

                    echo "Image URI: ${env.IMAGE_URI}"
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                echo 'Staging deployment will be configured in Step 3'
            }
        }

        stage('Smoke Test') {
            steps {
                echo 'Smoke testing will be configured in Step 3'
            }
        }

        stage('Deploy to Production') {
            steps {
                echo 'Production deployment will be configured in Step 3'
            }
        }
    }
}