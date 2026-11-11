
pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
        ECR_REPOSITORY = 'telecom-cicd-pipeline'
        CODEDEPLOY_BUCKET = 'telecom-cicd-codedeploy-artifacts-2026'
        CODEDEPLOY_APPLICATION = 'telecom-cicd-application'
        CODEDEPLOY_GROUP = 'telecom-cicd-deployment-group'
    }

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
                            --region "$AWS_REGION" \
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

        stage('Prepare CodeDeploy Bundle') {
            steps {
                script {
                    env.SAFE_BRANCH = (env.BRANCH_NAME ?: 'unknown')
                .replaceAll('[^A-Za-z0-9._-]', '-')

                    env.CODEDEPLOY_S3_KEY =
                "revisions/${env.SAFE_BRANCH}/${env.BUILD_NUMBER}/deployment-bundle.zip"

                    echo 'Checking CodeDeploy deployment files...'

                    sh '''
                set -eu

                test -f appspec.yml
                test -f scripts/before_install.sh
                test -f scripts/after_install.sh
                test -f scripts/validate_service.sh

                chmod +x scripts/*.sh

                echo "Creating deployment.env..."

                cat > deployment.env <<EOF
IMAGE_URI=${IMAGE_URI}
IMAGE_TAG=${IMAGE_TAG}
EOF

                echo "Creating deployment bundle..."

                rm -f deployment-bundle.zip

                zip -r deployment-bundle.zip \
                    appspec.yml \
                    scripts \
                    deployment.env

                echo "Checking deployment bundle contents..."

                unzip -l deployment-bundle.zip
            '''

                    echo 'Uploading deployment bundle to S3...'

                    sh '''
                aws s3 cp deployment-bundle.zip \
                    "s3://${CODEDEPLOY_BUCKET}/${CODEDEPLOY_S3_KEY}" \
                    --region "$AWS_REGION"

                echo "Verifying uploaded bundle..."

                aws s3api head-object \
                    --bucket "$CODEDEPLOY_BUCKET" \
                    --key "$CODEDEPLOY_S3_KEY" \
                    --region "$AWS_REGION"
            '''

                    echo "Deployment bundle uploaded: ${env.CODEDEPLOY_S3_KEY}"
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                echo 'Staging deployment is not yet connected to a separate CodeDeploy deployment group.'
                echo 'The production deployment group will not be used for staging.'
            }
        }

        stage('Smoke Test') {
            steps {
                echo 'Smoke testing will be configured when the staging deployment is implemented.'
            }
        }

        stage('Approve Production Deployment') {
            when {
                expression {
                    return env.BRANCH_NAME == 'main' ||
                           env.GIT_BRANCH == 'origin/main' ||
                           env.GIT_BRANCH == 'main'
                }
            }
            steps {
                input message: 'Approve deployment to the production Auto Scaling Group?',
                      ok: 'Deploy'
            }
        }

        stage('Deploy to Production') {
            when {
                expression {
                    return env.BRANCH_NAME == 'main' ||
                           env.GIT_BRANCH == 'origin/main' ||
                           env.GIT_BRANCH == 'main'
                }
            }

            steps {
                script {
                    echo 'Reading the previous successful image tag...'

                    env.PREVIOUS_IMAGE_TAG = sh(
                        script: """
                            aws s3 cp \
                            s3://${CODEDEPLOY_BUCKET}/rollback/last-successful-image.txt \
                            - --region ${AWS_REGION}
                        """,
                        returnStdout: true
                    ).trim()

                    if (!(env.PREVIOUS_IMAGE_TAG ==~ /^[0-9]+$/)) {
                        error('Previous successful image tag is missing or invalid.')
                    }

                    echo "Previous successful image tag: ${env.PREVIOUS_IMAGE_TAG}"
                    echo "New image tag: ${env.IMAGE_TAG}"

                    echo 'Checking deployment files...'

                    sh '''
                        set -eu

                        test -f appspec.yml
                        test -f scripts/before_install.sh
                        test -f scripts/after_install.sh
                        test -f scripts/validate_service.sh

                        chmod +x scripts/*.sh

                        echo "Creating deployment.env..."

                        cat > deployment.env <<EOF
IMAGE_URI=${IMAGE_URI}
IMAGE_TAG=${IMAGE_TAG}
EOF

                        echo "Creating deployment bundle..."

                        rm -f deployment-bundle.zip

                        zip -r deployment-bundle.zip \
                            appspec.yml \
                            scripts \
                            deployment.env

                        echo "Checking ZIP contents..."

                        unzip -l deployment-bundle.zip
                    '''

                    echo 'Uploading deployment bundle to S3...'

                    sh '''
                        aws s3 cp deployment-bundle.zip \
                        "s3://${CODEDEPLOY_BUCKET}/revisions/${BUILD_NUMBER}/deployment-bundle.zip" \
                        --region "$AWS_REGION"
                    '''

                    echo 'Starting CodeDeploy deployment...'

                    env.CODEDEPLOY_DEPLOYMENT_ID = sh(
                        script: """
                            aws deploy create-deployment \
                            --application-name ${CODEDEPLOY_APPLICATION} \
                            --deployment-group-name ${CODEDEPLOY_GROUP} \
                            --s3-location bucket=${CODEDEPLOY_BUCKET},key=${env.CODEDEPLOY_S3_KEY},bundleType=zip \
                            --region ${AWS_REGION} \
                            --query deploymentId \
                            --output text
                        """,
                        returnStdout: true
                    ).trim()

                    echo "CodeDeploy deployment ID: ${env.CODEDEPLOY_DEPLOYMENT_ID}"

                    echo 'Waiting for CodeDeploy deployment to finish...'

                    timeout(time: 15, unit: 'MINUTES') {
                        sh """
                            aws deploy wait deployment-successful \
                            --deployment-id ${env.CODEDEPLOY_DEPLOYMENT_ID} \
                            --region ${AWS_REGION}
                        """
                    }

                    echo 'CodeDeploy deployment succeeded.'

                    echo 'Updating the last successful image tag in S3...'

                    sh '''
                        printf '%s\\n' "$IMAGE_TAG" | \
                        aws s3 cp - \
                        "s3://${CODEDEPLOY_BUCKET}/rollback/last-successful-image.txt" \
                        --region "$AWS_REGION"
                    '''

                    echo "Last successful image updated to ${env.IMAGE_TAG}"
                }
            }
        }
    }

    post {
        success {
            echo 'Jenkins pipeline completed successfully.'
        }

        failure {
            echo 'Jenkins pipeline failed. Check the failed stage and CodeDeploy deployment status.'
            echo 'CodeDeploy automatic rollback should handle a failed deployment if enabled in the deployment group.'
        }
    }
}
