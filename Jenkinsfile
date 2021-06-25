pipeline {
    agent { label 'x86' }

    environment {
        REPO_URL = "https://repo.guldner.eu/repository/archlinux/"
    }

    stages {
        stage('Prepare') {
            steps {
                cleanWorkspace()
                sh 'set -x'
                sh 'wget https://repo.guldner.eu/repository/archlinux/x86_64/dasbaumwolltier.db.tar.zst && ' + 
                    'wget https://repo.guldner.eu/repository/archlinux/x86_64/dasbaumwolltier.db.tar.zst.sig && ' +
                    'wget https://repo.guldner.eu/repository/archlinux/x86_64/dasbaumwolltier.files.tar.zst && ' +
                    'wget https://repo.guldner.eu/repository/archlinux/x86_64/dasbaumwolltier.files.tar.zst.sig || ' +
                    'repo-add dasbaumwolltier.db.tar.zst'
                sh 'curl "https://keys.openpgp.org/vks/v1/by-fingerprint/746BC93D5F08C5A4369F4DDB10BF99E6998249B6" > sign.crt'
                sh 'ls -la'
            }
        }

        stage('Build docker image') {
            steps {
                sh 'docker -t aur-build-image:v1 build . | tee docker-build.log'
            }
        }

        stage('Build packages') {
            steps {
                sh 'set +x'

                withCredentials([file(credentialsId: 'buildbot-guldner.eu-key', variable: 'KEYFILE')]) {
                    sh 'cp $KEYFILE sign.key'
                    sh 'chmod 777 sign.key'
                }

                withCredentials([usernamePassword(credentialsId: 'archlinux-nexus-oss', passwordVariable: 'REPO_PASS', usernameVariable: 'REPO_USER')]) {
                    sh 'docker run -e REPO_URL="$REPO_URL" -e REPO_USER="$REPO_USER" -e REPO_PASS="$REPO_PASS" -e SIGN_EMAIL="746BC93D5F08C5A4369F4DDB10BF99E6998249B6"' +
                        '-v "$(realpath sign.key):/build/sign.key"' +
                        '-v "$(realpath sign.crt):/build/sign.crt"' +
                        '-v "$(realpath dasbaumwolltier.db.tar.zst):/build/dasbaumwolltier.db.tar.zst"' +
                        '-v "$(realpath dasbaumwolltier.db.tar.zst.sig):/build/dasbaumwolltier.db.tar.zst.sig"' +
                        '-v "$(realpath dasbaumwolltier.files.tar.zst):/build/dasbaumwolltier.files.tar.zst"' +
                        '-v "$(realpath dasbaumwolltier.files.tar.zst.sig):/build/dasbaumwolltier.files.tar.zst.sig"' +
                        'aur-build-image:v1'
                }
            }
        }

        stage('Clean up') {
            sh 'rm sign.key'
            sh 'set -x'
            sh 'docker rm ${JOB_BASE_NAME}'
        }
    }
}