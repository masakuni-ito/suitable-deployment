#!/bin/bash -u

SUDO_PASSWORD=""
IDENTIFY_FILE_PATH=""

DEPLOY_REPOSITORY=git@github.com:path/to.git
DEPLOY_BRANCH=master

REMOTE_HOST=127.0.0.1
REMOTE_PORT=22
REMOTE_USER=lig
REMOTE_CURRENT_DIR=/path/to/current
REMOTE_RELEASES_DIR=/path/to/release
REMOTE_WEB_USER=nginx

KEEP_RELEASES=5

PATH=/usr/local/opt/curl/bin:$PATH
TMP_PATH="/tmp/repo"

latest=`date +"%Y%m%d%I%M%S"`

# get login identify
if [ "$IDENTIFY_FILE_PATH" == "" ]; then
	echo "INFO: sshの秘密鍵を絶対パスで指定指定してください。"
	read -p "(ex.) /Users/xxxxxx/.ssh/id_yyyy: " IDENTIFY_FILE_PATH
	echo ""
fi

if [ "$SUDO_PASSWORD" == "" ]; then
	echo "INFO: ${REMOTE_USER}@${REMOTE_HOST} のパスワードを入力してください。"
	read -s -p "password: " SUDO_PASSWORD
	echo ""
fi

# prepare
ssh -i ${IDENTIFY_FILE_PATH} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "echo $SUDO_PASSWORD | sudo -S bash -c 'mkdir -p ${REMOTE_RELEASES_DIR} && chown ${REMOTE_WEB_USER}:${REMOTE_WEB_USER} ${REMOTE_RELEASES_DIR} && chmod 777 ${REMOTE_RELEASES_DIR}'"

mkdir -p ${TMP_PATH}
if [ ! -e ${TMP_PATH}/org ]; then
	git clone ${DEPLOY_REPOSITORY} ${TMP_PATH}/org
fi

# build process
cd ${TMP_PATH}/org
git checkout ${DEPLOY_BRANCH} && git pull origin ${DEPLOY_BRANCH} && git reset --hard

## has npm packages
if [ -e package.json ]; then
	npm install
fi

## has composer packages
if [ -e composer.json ]; then
	composer install
fi

## save code for deployment
mkdir -p ${TMP_PATH}/seed/${latest}
rsync -rlpgoDvz ${TMP_PATH}/org/ ${TMP_PATH}/seed/${latest}

# deploy process
rsync -e "ssh -i ${IDENTIFY_FILE_PATH} -p ${REMOTE_PORT}" -rlpgoDvz --delete ${TMP_PATH}/seed/${latest}/ ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_RELEASES_DIR}/${latest}
ssh -i ${IDENTIFY_FILE_PATH} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "echo $SUDO_PASSWORD | sudo -S bash -c 'chown -R ${REMOTE_WEB_USER}:${REMOTE_WEB_USER} ${REMOTE_RELEASES_DIR}/${latest} && if [ -d ${REMOTE_CURRENT_DIR} ]; then rm -rf ${REMOTE_CURRENT_DIR}; fi && ln -nfs ${REMOTE_RELEASES_DIR}/${latest} ${REMOTE_CURRENT_DIR}'"

# clean up
delete_releases=`expr ${KEEP_RELEASES} + 1`

## delete old code in local
dir=""
for dir in `ls -t ${TMP_PATH}/seed | tail -n +${delete_releases}`; do rm -rf ${TMP_PATH}/seed/${dir}; done

## delete old code in remote
ssh -i ${IDENTIFY_FILE_PATH} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "echo $SUDO_PASSWORD | sudo -S bash -c 'for dir in \`ls -t ${REMOTE_RELEASES_DIR} | tail -n +${delete_releases}\`; do rm -rf ${REMOTE_RELEASES_DIR}/\${dir}; done'"

## restart web server

