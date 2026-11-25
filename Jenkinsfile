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
        STAGING_CODEDEPLOY_GROUP = 'telecom-cicd-staging-group'

        STAGING_URL = 'http://telecom-cicd-staging-alb-1656323563.us-east-1.elb.amazonaws.com'
        PRODUCTION_URL = 'http://telecom-cicd-alb-378185628.us-east-1.elb.amazonaws.com'
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    echo 'Checking out source code...'

                    def checkoutInfo = checkout scm

                    // Use the branch configured in Jenkins Pipeline SCM.
                    // Fall back to checkout information if necessary.
                    def rawBranch = (
                        scm.branches?.getAt(0)?.name ?:
                        checkoutInfo?.GIT_BRANCH ?:
                        env.BRANCH_NAME ?:
                        env.GIT_BRANCH ?:
                        ''
                    ).toString().trim()

                    echo "SCM branch reference: ${rawBranch}"

                    // Normalize common Git branch formats.
                    // Examples:
                    // origin/dev -> dev
                    // */dev -> dev
                    // refs/heads/main -> main
                    def branch = rawBranch
                        .replace('refs/remotes/origin/', '')
                        .replace('refs/heads/', '')
                        .replace('origin/', '')
                        .replace('*/', '')

                    // Fail closed for unrecognized branches.
                    if (!(branch in ['dev', 'main'])) {
                        error(
                            "Unsupported deployment branch: ${rawBranch}. " +
                            'Deployment is blocked.'
                        )
                    }

                    // Verify the checked-out commit.
                    def actualCommit = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()

                    def expectedCommit = sh(
                        script: "git rev-parse refs/remotes/origin/${branch}",
                        returnStdout: true
                    ).trim()

                    if (actualCommit != expectedCommit) {
                        error(
                            "Checked-out commit does not match origin/${branch}. " +
                            'Deployment is blocked.'
                        )
                    }

                    env.RESOLVED_BRANCH = branch

                    env.IS_PRODUCTION_BRANCH =
                        (branch == 'main') ? 'true' : 'false'

                    env.IS_STAGING_BRANCH =
                        (branch == 'dev') ? 'true' : 'false'

                    // Initialize runtime deployment tracking variables.
                    env.DEPLOYMENT_STARTED = 'false'
                    env.PREVIOUS_REVISION_KEY = ''
                    env.CODEDEPLOY_DEPLOYMENT_ID = ''
                    env.STAGING_DEPLOYMENT_ID = ''

                    echo "Resolved branch: ${env.RESOLVED_BRANCH}"
                    echo "Production branch: ${env.IS_PRODUCTION_BRANCH}"
                    echo "Staging branch: ${env.IS_STAGING_BRANCH}"
                    echo "Verified commit: ${actualCommit}"
                }
            }
        }

        stage('Secret Scanning') {
            steps {
                echo 'Scanning repository for exposed secrets...'

                sh '''
                    trufflehog --no-update git file://. --fail
                '''
            }
        }

        stage('Verify Application Secrets') {
            steps {
                echo 'Verifying AWS Secrets Manager access...'

                sh '''
                    set +x

                    aws secretsmanager describe-secret \
                      --secret-id telecom-cicd/app \
                      --region "$AWS_REGION" \
                      --query ARN \
                      --output text > /dev/null

                    echo 'Secrets Manager access verified.'
                '''
            }
        }

        stage('Build') {
            steps {
                echo 'Installing Python dependencies...'

                sh '''
                    set -eu

                    python3 --version
                    python3 -m venv .venv

                    .venv/bin/python -m pip install --upgrade pip
                    .venv/bin/python -m pip install -r requirements.txt
                    .venv/bin/python -m pip install pytest-cov

                    echo 'Python dependencies installed successfully.'
                '''
            }
        }

        stage('Unit Test') {
            steps {
                echo 'Running automated unit tests...'

                sh '''
                    set -eu

                    .venv/bin/python -m pytest tests/ \
                      -v \
                      --cov=main \
                      --cov-report=term-missing \
                      --cov-report=xml:coverage.xml \
                      --junitxml=test-results.xml

                    test -s coverage.xml

                    echo 'Unit tests passed.'
                '''
            }

            post {
                always {
                    junit(
                        allowEmptyResults: true,
                        testResults: 'test-results.xml'
                    )

                    archiveArtifacts(
                        artifacts: 'coverage.xml',
                        allowEmptyArchive: true
                    )
                }
            }
        }

        stage('SonarQube Scan') {
            steps {
                script {
                    def scannerHome = tool 'SonarScanner'

                    withSonarQubeEnv('SonarQube') {
                        sh """
                            "${scannerHome}/bin/sonar-scanner"
                        """
                    }
                }
            }
        }

        stage('SonarQube Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    env.AWS_ACCOUNT_ID = sh(
                        script: '''
                            aws sts get-caller-identity \
                              --query Account \
                              --output text
                        ''',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = env.BUILD_NUMBER

                    env.IMAGE_URI =
                        "${env.AWS_ACCOUNT_ID}.dkr.ecr." +
                        "${env.AWS_REGION}.amazonaws.com/" +
                        "${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"

                    sh '''
                        set -eu

                        test -f Dockerfile

                        aws ecr get-login-password \
                          --region "$AWS_REGION" | \
                          docker login \
                            --username AWS \
                            --password-stdin \
                            "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

                        docker build -t "$IMAGE_URI" .
                        docker push "$IMAGE_URI"
                    '''

                    echo "Pushed Docker image: ${env.IMAGE_URI}"
                }
            }
        }

        stage('Prepare CodeDeploy Bundle') {
            when {
                expression {
                    env.IS_STAGING_BRANCH == 'true' ||
                    env.IS_PRODUCTION_BRANCH == 'true'
                }
            }

            steps {
                script {
                    def deployBranch =
                        env.IS_PRODUCTION_BRANCH == 'true' ?
                        'main' : 'dev'

                    env.CODEDEPLOY_S3_KEY =
                        "revisions/${deployBranch}/" +
                        "${env.BUILD_NUMBER}/deployment-bundle.zip"

                    echo "Preparing deployment for ${deployBranch}"

                    sh '''
                        set -eu

                        test -f appspec.yml
                        test -f scripts/before_install.sh
                        test -f scripts/after_install.sh
                        test -f scripts/validate_service.sh

                        chmod +x scripts/*.sh

                        printf 'IMAGE_URI=%s\\nIMAGE_TAG=%s\\n' \
                          "$IMAGE_URI" "$IMAGE_TAG" \
                          > deployment.env

                        rm -f deployment-bundle.zip

                        zip -r deployment-bundle.zip \
                          appspec.yml \
                          scripts \
                          deployment.env

                        unzip -l deployment-bundle.zip

                        aws s3 cp deployment-bundle.zip \
                          "s3://${CODEDEPLOY_BUCKET}/${CODEDEPLOY_S3_KEY}" \
                          --region "$AWS_REGION"

                        aws s3api head-object \
                          --bucket "$CODEDEPLOY_BUCKET" \
                          --key "$CODEDEPLOY_S3_KEY" \
                          --region "$AWS_REGION" \
                          --query ContentLength \
                          --output text
                    '''

                    echo "Prepared revision: ${env.CODEDEPLOY_S3_KEY}"
                }
            }
        }

        stage('Deploy to Staging') {
            when {
                expression {
                    env.IS_STAGING_BRANCH == 'true'
                }
            }

            steps {
                script {
                    echo 'Starting staging CodeDeploy deployment...'

                    env.STAGING_DEPLOYMENT_ID = sh(
                        script: '''
                            aws deploy create-deployment \
                              --application-name "$CODEDEPLOY_APPLICATION" \
                              --deployment-group-name "$STAGING_CODEDEPLOY_GROUP" \
                              --s3-location "bucket=$CODEDEPLOY_BUCKET,key=$CODEDEPLOY_S3_KEY,bundleType=zip" \
                              --file-exists-behavior OVERWRITE \
                              --region "$AWS_REGION" \
                              --query deploymentId \
                              --output text
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "Staging deployment ID: ${env.STAGING_DEPLOYMENT_ID}"

                    try {
                        timeout(time: 15, unit: 'MINUTES') {
                            sh '''
                                aws deploy wait deployment-successful \
                                  --deployment-id "$STAGING_DEPLOYMENT_ID" \
                                  --region "$AWS_REGION"
                            '''
                        }

                        echo 'Staging CodeDeploy deployment succeeded.'
                    } catch (Exception stagingFailure) {
                        echo "Staging deployment failed: ${stagingFailure}"

                        sh '''
                            aws deploy get-deployment \
                              --deployment-id "$STAGING_DEPLOYMENT_ID" \
                              --region "$AWS_REGION" \
                              --query 'deploymentInfo.{Status:status,Error:errorInformation,Rollback:rollbackInfo}' \
                              --output json || true
                        '''

                        throw stagingFailure
                    }
                }
            }
        }

        stage('Smoke Test (Staging)') {
            when {
                expression {
                    env.IS_STAGING_BRANCH == 'true'
                }
            }

            steps {
                echo 'Testing staging application health...'

                sh '''
                    set -eu

                    curl \
                      --fail \
                      --show-error \
                      --retry 5 \
                      --retry-delay 3 \
                      --max-time 10 \
                      "$STAGING_URL/health"

                    echo 'Staging smoke test passed.'
                '''
            }
        }

        stage('Approve Production Deployment') {
            when {
                expression {
                    env.IS_PRODUCTION_BRANCH == 'true'
                }
            }

            steps {
                input(
                    message: 'Deploy the prepared revision to the production Auto Scaling Group?',
                    ok: 'Deploy'
                )
            }
        }

        stage('Deploy to Production') {
            when {
                expression {
                    env.IS_PRODUCTION_BRANCH == 'true'
                }
            }

            steps {
                script {
                    // Retrieve the last successful CodeDeploy revision.
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

                    if (env.PREVIOUS_REVISION_KEY) {
                        echo "Previous verified revision: ${env.PREVIOUS_REVISION_KEY}"
                    } else {
                        echo(
                            'No previous successful CodeDeploy revision. ' +
                            'Initial deployment rollback is unavailable.'
                        )
                    }

                    // Start the new production deployment.
                    env.CODEDEPLOY_DEPLOYMENT_ID = sh(
                        script: '''
                            aws deploy create-deployment \
                              --application-name "$CODEDEPLOY_APPLICATION" \
                              --deployment-group-name "$CODEDEPLOY_GROUP" \
                              --s3-location "bucket=$CODEDEPLOY_BUCKET,key=$CODEDEPLOY_S3_KEY,bundleType=zip" \
                              --file-exists-behavior OVERWRITE \
                              --region "$AWS_REGION" \
                              --query deploymentId \
                              --output text
                        ''',
                        returnStdout: true
                    ).trim()

                    env.DEPLOYMENT_STARTED = 'true'

                    echo(
                        'Production CodeDeploy deployment: ' +
                        "${env.CODEDEPLOY_DEPLOYMENT_ID}"
                    )

                    try {
                        timeout(time: 20, unit: 'MINUTES') {
                            sh '''
                                aws deploy wait deployment-successful \
                                  --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                                  --region "$AWS_REGION"
                            '''
                        }

                        // Record the successful production revision.
                        sh '''
                            set -eu

                            printf '%s\\n' "$IMAGE_TAG" | \
                              aws s3 cp - \
                              "s3://${CODEDEPLOY_BUCKET}/rollback/last-successful-image.txt" \
                              --region "$AWS_REGION"

                            printf '%s\\n' "$CODEDEPLOY_S3_KEY" | \
                              aws s3 cp - \
                              "s3://${CODEDEPLOY_BUCKET}/rollback/last-successful-revision.txt" \
                              --region "$AWS_REGION"
                        '''

                        echo(
                            'Production deployment succeeded. ' +
                            "Recorded image tag ${env.IMAGE_TAG}."
                        )
                    } catch (Exception deploymentFailure) {
                        echo(
                            'Deployment did not report success: ' +
                            "${deploymentFailure}"
                        )

                        sh '''
                            aws deploy get-deployment \
                              --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                              --region "$AWS_REGION" \
                              --query 'deploymentInfo.{Status:status,Error:errorInformation,Rollback:rollbackInfo}' \
                              --output json || true
                        '''

                        def failedStatus = sh(
                            script: '''
                                aws deploy get-deployment \
                                  --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                                  --region "$AWS_REGION" \
                                  --query 'deploymentInfo.status' \
                                  --output text
                            ''',
                            returnStdout: true
                        ).trim()

                        // Never start a competing rollback while the
                        // original deployment is still active.
                        if (!(failedStatus in ['Failed', 'Stopped'])) {
                            error(
                                "Deployment status is ${failedStatus}. " +
                                'Manual fallback withheld.'
                            )
                        }

                        // CodeDeploy automatic rollback is primary.
                        def rollbackId = sh(
                            script: '''
                                aws deploy get-deployment \
                                  --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                                  --region "$AWS_REGION" \
                                  --query 'deploymentInfo.rollbackInfo.rollbackDeploymentId' \
                                  --output text
                            ''',
                            returnStdout: true
                        ).trim()

                        if (!rollbackId || rollbackId == 'None') {
                            sleep time: 20, unit: 'SECONDS'

                            rollbackId = sh(
                                script: '''
                                    aws deploy get-deployment \
                                      --deployment-id "$CODEDEPLOY_DEPLOYMENT_ID" \
                                      --region "$AWS_REGION" \
                                      --query 'deploymentInfo.rollbackInfo.rollbackDeploymentId' \
                                      --output text
                                ''',
                                returnStdout: true
                            ).trim()
                        }

                        if (rollbackId && rollbackId != 'None') {
                            echo "Automatic rollback started: ${rollbackId}"

                            def autoRollbackOk = sh(
                                script: """
                                    aws deploy wait deployment-successful \\
                                      --deployment-id '${rollbackId}' \\
                                      --region '${env.AWS_REGION}'
                                """,
                                returnStatus: true
                            ) == 0

                            if (autoRollbackOk) {
                                error(
                                    'New deployment failed. ' +
                                    "Automatic rollback ${rollbackId} succeeded. " +
                                    'Tracking files unchanged.'
                                )
                            }

                            echo(
                                'Automatic rollback did not succeed. ' +
                                'Evaluating fallback.'
                            )
                        }

                        if (!env.PREVIOUS_REVISION_KEY) {
                            error(
                                'No previous successful revision exists. ' +
                                'Manual repair required.'
                            )
                        }

                        // Ensure no other deployment is active.
                        def ongoing = sh(
                            script: '''
                                aws deploy list-deployments \
                                  --application-name "$CODEDEPLOY_APPLICATION" \
                                  --deployment-group-name "$CODEDEPLOY_GROUP" \
                                  --include-only-statuses Created Queued InProgress Baking \
                                  --region "$AWS_REGION" \
                                  --query 'length(deployments)' \
                                  --output text
                            ''',
                            returnStdout: true
                        ).trim()

                        if (ongoing != '0') {
                            error(
                                'Another CodeDeploy deployment is active. ' +
                                'Fallback withheld to avoid a race.'
                            )
                        }

                        echo(
                            'Attempting Jenkins fallback using ' +
                            "${env.PREVIOUS_REVISION_KEY}"
                        )

                        def fallbackId = sh(
                            script: """
                                aws deploy create-deployment \\
                                  --application-name '${env.CODEDEPLOY_APPLICATION}' \\
                                  --deployment-group-name '${env.CODEDEPLOY_GROUP}' \\
                                  --s3-location 'bucket=${env.CODEDEPLOY_BUCKET},key=${env.PREVIOUS_REVISION_KEY},bundleType=zip' \\
                                  --file-exists-behavior OVERWRITE \\
                                  --region '${env.AWS_REGION}' \\
                                  --query deploymentId \\
                                  --output text
                            """,
                            returnStdout: true
                        ).trim()

                        echo "Jenkins fallback deployment: ${fallbackId}"

                        def fallbackOk = sh(
                            script: """
                                aws deploy wait deployment-successful \\
                                  --deployment-id '${fallbackId}' \\
                                  --region '${env.AWS_REGION}'
                            """,
                            returnStatus: true
                        ) == 0

                        if (fallbackOk) {
                            error(
                                'New deployment failed. ' +
                                "Jenkins fallback ${fallbackId} succeeded. " +
                                'Tracking files unchanged.'
                            )
                        }

                        error(
                            'New deployment and Jenkins fallback ' +
                            "${fallbackId} failed. Investigate CodeDeploy."
                        )
                    }
                }
            }
        }

        stage('Smoke Test (Production)') {
            when {
                expression {
                    env.IS_PRODUCTION_BRANCH == 'true'
                }
            }

            steps {
                echo 'Testing production application health...'

                sh '''
                    set -eu

                    curl \
                      --fail \
                      --show-error \
                      --retry 5 \
                      --retry-delay 3 \
                      --connect-timeout 10 \
                      --max-time 10 \
                      "$PRODUCTION_URL/health"

                    echo 'Production smoke test passed.'
                '''
            }
        }
    }

    post {
        success {
            echo(
                'Pipeline completed successfully. ' +
                'CI quality gates passed and branch-specific ' +
                'deployment stages completed.'
            )
        }

        failure {
            echo(
                'Pipeline FAILED. Check the failed stage ' +
                'and any CodeDeploy deployment or rollback IDs.'
            )
        }

        aborted {
            echo(
                'Pipeline ABORTED. Check for a timeout, ' +
                'manual cancellation or pending approval.'
            )
        }
    }
}
