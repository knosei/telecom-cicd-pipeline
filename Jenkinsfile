pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                echo 'Checking out source code'
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
                echo 'Docker and ECR will be configured in Step 3'
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