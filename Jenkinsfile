pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        AWS_REGION = 'us-east-1'
        ECR_REPOSITORY = 'telecom-cicd-pipeline'
        CODEDEPLOY_BUCKET = 'telecom-cicd-codedeploy-artifacts-2026'
        CODEDEPLOY_APPLICATION = 'telecom-cicd-application'
        CODEDEPLOY_GROUP = 'telecom-cicd-deployment-group'
        DEPLOYMENT_STARTED = 'false'
        PREVIOUS_REVISION_KEY = ''
        CODEDEPLOY_DEPLOYMENT_ID = ''
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    // The job currently builds dev. Only origin/main/main can deploy to production.
                    env.IS_PRODUCTION_BRANCH = (
                        env.BRANCH_NAME == 'main' ||
                        env.GIT_BRANCH == 'origin/main' ||
                        env.GIT_BRANCH == 'main'
                    ) ? 'true' : 'false'
                    echo "Production branch: ${env.IS_PRODUCTION_BRANCH}"
                }
            }
        }

        stage('Secret Scanning') {
            steps {
                sh 'trufflehog --no-update git file://. --fail'
            }
        }

        stage('Verify Application Secrets') {
            steps {
                // Only verify access; application EC2 fetches values during deployment.
                // Never copy secret values into the Jenkins Pipeline environment.
                sh '''
                    set +x
                    aws secretsmanager describe-secret \
                      --secret-id telecom-cicd/app \
                      --region "$AWS_REGION" \
                      --query ARN --output text > /dev/null
                    echo 'Secrets Manager access verified (values not retrieved).'
                '''
            }
        }

        stage('Build') {
            steps {
                echo 'TODO: install and validate Python project dependencies (not yet a build gate).'
            }
        }

        stage('Unit Test') {
            steps {
                echo 'TODO: run pytest and enforce coverage (not yet a test gate).'
            }
        }

        stage('SonarQube Scan') {
            steps {
                echo 'TODO: run SonarQube and wait for quality gate (not yet a security/quality gate).'
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
                        test -f Dockerfile
                        aws ecr get-login-password --region "$AWS_REGION" | \
                          docker login --username AWS --password-stdin \
                          "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
                        docker build -t "$IMAGE_URI" .
                        docker push "$IMAGE_URI"
                    '''
                    echo "Pushed ${env.IMAGE_URI}"
                }
            }
        }

        stage('Prepare CodeDeploy Bundle') {
            when { expression { env.IS_PRODUCTION_BRANCH == 'true' } }
            steps {
                script {
                    env.CODEDEPLOY_S3_KEY = "revisions/main/${env.BUILD_NUMBER}/deployment-bundle.zip"
                    sh '''
                        set -eu
                        test -f appspec.yml
                        test -f scripts/before_install.sh
                        test -f scripts/after_install.sh
                        test -f scripts/validate_service.sh
                        chmod +x scripts/*.sh
                        printf 'IMAGE_URI=%s\\nIMAGE_TAG=%s\\n' "$IMAGE_URI" "$IMAGE_TAG" > deployment.env
                        rm -f deployment-bundle.zip
                        zip -r deployment-bundle.zip appspec.yml scripts deployment.env
                        unzip -l deployment-bundle.zip
                        aws s3 cp deployment-bundle.zip \
                          "s3://${CODEDEPLOY_BUCKET}/${CODEDEPLOY_S3_KEY}" \
                          --region "$AWS_REGION"
                        aws s3api head-object \
                          --bucket "$CODEDEPLOY_BUCKET" \
                          --key "$CODEDEPLOY_S3_KEY" \
                          --region "$AWS_REGION" \
                          --query ContentLength --output text
                    '''
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                echo 'Not configured: staging requires its own deployment group and application instances.'
                echo 'No production resources will be used for staging.'
            }
        }

        stage('Smoke Test (Staging)') {
            steps {
                echo 'Not configured: staging smoke tests require a deployed staging environment.'
            }
        }

        stage('Approve Production Deployment') {
            when { expression { env.IS_PRODUCTION_BRANCH == 'true' } }
            steps {
                input message: 'Deploy the prepared revision to the production Auto Scaling Group?', ok: 'Deploy'
            }
        }

        stage('Deploy to Production') {
            when { expression { env.IS_PRODUCTION_BRANCH == 'true' } }
            steps {
                script {
                    // Use CodeDeploy's actual last successful revision, NOT an unverified S3 tag.
                    def priorDeploymentId = sh(
                        script: '''
                            aws deploy get-deployment-group \
                              --application-name "$CODEDEPLOY_APPLICATION" \
                              --deployment-group-name "$CODEDEPLOY_GROUP" \
                              --region "$AWS_REGION" \
                              --query 'deploymentGroupInfo.lastSuccessfulDeployment.deploymentId' \
                              --output text
                        ''',
                        returnStdout: true
                    ).trim()
                    if (priorDeploymentId && priorDeploymentId != 'None') {
                        env.PREVIOUS_REVISION_KEY = sh(
                            script: """
                                aws deploy get-deployment \\
                                  --deployment-id '${priorDeploymentId}' \\
                                  --region '${env.AWS_REGION}' \\
                                  --query 'deploymentInfo.revision.s3Location.key' \\
                                  --output text
                            """,
                            returnStdout: true
                        ).trim()
                        if (env.PREVIOUS_REVISION_KEY == 'None') {
                            env.PREVIOUS_REVISION_KEY = ''
                        }
                    }
                    echo env.PREVIOUS_REVISION_KEY ?
                        "Previous verified revision: ${env.PREVIOUS_REVISION_KEY}" :
                        'No previous successful CodeDeploy revision: initial deployment, automatic rollback unavailable.'

                    env.CODEDEPLOY_DEPLOYMENT_ID = sh(
                        script: '''
                            aws deploy create-deployment \
                              --application-name "$CODEDEPLOY_APPLICATION" \
                              --deployment-group-name "$CODEDEPLOY_GROUP" \
                              --s3-location "bucket=$CODEDEPLOY_BUCKET,key=$CODEDEPLOY_S3_KEY,bundleType=zip" \
                              --file-exists-behavior OVERWRITE \
                              --region "$AWS_REGION" \
                              --query deploymentId --output text
                        ''',
                        returnStdout: true
                    ).trim()
                    env.DEPLOYMENT_STARTED = 'true'
                    echo "CodeDeploy deployment: ${env.CODEDEPLOY_DEPLOYMENT_ID}"

                    try {
                        timeout(time: 15, unit: 'MINUTES') {
                            sh '''
                                aws deploy wait deployment-successful \
                                  --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                                  --region "$AWS_REGION"
                            '''
                        }
                        // This is the ONLY place a new successful tag is recorded.
                        sh '''
                            set -eu
                            printf '%s\\n' "$IMAGE_TAG" | aws s3 cp - \
                              "s3://${CODEDEPLOY_BUCKET}/rollback/last-successful-image.txt" \
                              --region "$AWS_REGION"
                            printf '%s\\n' "$CODEDEPLOY_S3_KEY" | aws s3 cp - \
                              "s3://${CODEDEPLOY_BUCKET}/rollback/last-successful-revision.txt" \
                              --region "$AWS_REGION"
                        '''
                        echo "Deployment succeeded; recorded successful image ${env.IMAGE_TAG}."
                    } catch (Exception deploymentFailure) {
                        echo "Deployment did not report success: ${deploymentFailure}"
                        sh '''
                            aws deploy get-deployment \
                              --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                              --region "$AWS_REGION" \
                              --query 'deploymentInfo.{Status:status,Error:errorInformation,Rollback:rollbackInfo}' \
                              --output json || true
                        '''
                        def failedStatus = sh(
                            script: '''
                                aws deploy get-deployment --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                                  --region "$AWS_REGION" --query 'deploymentInfo.status' --output text
                            ''', returnStdout: true
                        ).trim()
                        if (!(failedStatus in ['Failed', 'Stopped'])) {
                            error("Deployment status is ${failedStatus}; not starting a competing rollback. Inspect CodeDeploy.")
                        }

                        // CodeDeploy automatic rollback is primary. Wait for its separate deployment.
                        def rollbackId = sh(
                            script: '''
                                aws deploy get-deployment --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                                  --region "$AWS_REGION" \
                                  --query 'deploymentInfo.rollbackInfo.rollbackDeploymentId' --output text
                            ''', returnStdout: true
                        ).trim()
                        if (!rollbackId || rollbackId == 'None') {
                            sleep time: 20, unit: 'SECONDS'
                            rollbackId = sh(
                                script: '''
                                    aws deploy get-deployment --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                                      --region "$AWS_REGION" \
                                      --query 'deploymentInfo.rollbackInfo.rollbackDeploymentId' --output text
                                ''', returnStdout: true
                            ).trim()
                        }
                        if (rollbackId && rollbackId != 'None') {
                            echo "CodeDeploy started automatic rollback: ${rollbackId}"
                            def autoRollbackOk = sh(
                                script: "aws deploy wait deployment-successful --deployment-id '${rollbackId}' --region '${env.AWS_REGION}'",
                                returnStatus: true
                            ) == 0
                            if (autoRollbackOk) {
                                error("Deployment failed; CodeDeploy automatic rollback ${rollbackId} succeeded. Tracking file unchanged.")
                            }
                            echo "Automatic rollback ${rollbackId} failed; evaluating manual fallback."
                        }
                        if (!env.PREVIOUS_REVISION_KEY) {
                            error('No previous successful revision exists. Initial deployment failed; manual repair required.')
                        }

                        // Do not race another deployment still in progress.
                        def ongoing = sh(
                            script: '''
                                aws deploy list-deployments \
                                  --application-name "$CODEDEPLOY_APPLICATION" \
                                  --deployment-group-name "$CODEDEPLOY_GROUP" \
                                  --include-only-statuses Created Queued InProgress Baking \
                                  --region "$AWS_REGION" --query 'length(deployments)' --output text
                            ''', returnStdout: true
                        ).trim()
                        if (ongoing != '0') {
                            error('Another CodeDeploy deployment is active; manual fallback withheld to avoid a race.')
                        }
                        echo "Attempting Jenkins fallback using ${env.PREVIOUS_REVISION_KEY}"
                        def fallbackId = sh(
                            script: """
                                aws deploy create-deployment \\
                                  --application-name '${env.CODEDEPLOY_APPLICATION}' \\
                                  --deployment-group-name '${env.CODEDEPLOY_GROUP}' \\
                                  --s3-location 'bucket=${env.CODEDEPLOY_BUCKET},key=${env.PREVIOUS_REVISION_KEY},bundleType=zip' \\
                                  --file-exists-behavior OVERWRITE \\
                                  --region '${env.AWS_REGION}' \\
                                  --query deploymentId --output text
                            """, returnStdout: true
                        ).trim()
                        echo "Jenkins fallback deployment: ${fallbackId}"
                        def fallbackOk = sh(
                            script: "aws deploy wait deployment-successful --deployment-id '${fallbackId}' --region '${env.AWS_REGION}'",
                            returnStatus: true
                        ) == 0
                        if (fallbackOk) {
                            error("New deployment failed; Jenkins fallback ${fallbackId} succeeded. Tracking file unchanged.")
                        }
                        error("New deployment and Jenkins fallback ${fallbackId} failed. Investigate CodeDeploy immediately.")
                    }
                }
            }
        }
    }

    post {
        success { echo 'Pipeline finished. NOTE: Build/tests/SonarQube/staging are still placeholders.' }
        failure { echo 'Pipeline FAILED. Check the deployment and rollback IDs above if a deployment started.' }
    }
}
