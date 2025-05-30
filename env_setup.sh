#!/bin/env bash

# ---------------------
# configuration section
# ---------------------

CONTAINER_NAME=laboratory
IMAGE_NAME=development
USER_NAME=developer
USER_UID=1000
USER_GID=1000
HOME_DIRECTORY=${HOME}/repository/pod/mount/home
WORK_DIRECTORY=${HOME}/repository/pod/mount/data/${CONTAINER_NAME}

# ----------------
# template section
# ----------------

CONTAINER_CONFIG="FROM registry.fedoraproject.org/fedora:latest
RUN dnf install -y git-core fuse-overlayfs less ncurses neovim podman python-pip --exclude container-selinux
RUN dnf update -y
RUN python3 -m pip install ansible-core ansible-navigator
RUN groupadd -g ${USER_GID} ${USER_NAME}
RUN useradd -u ${USER_UID} -g ${USER_NAME} ${USER_NAME}
RUN mkdir -p /home/${USER_NAME}/.config /home/${USER_NAME}/.ssh /home/${USER_NAME}/${CONTAINER_NAME}
RUN echo 'alias vi=nvim' > /etc/profile.d/neovim.sh
RUN echo 'export EDITOR=\"\$(which nvim)\"' >> /etc/profile.d/neovim.sh
COPY upload /tmp/upload
RUN cp -R /tmp/upload/.[a-z]* /tmp/upload/* /home/${USER_NAME}/.
RUN chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}
RUN echo '${USER_NAME}:10000:5000' >/etc/subuid
RUN echo '${USER_NAME}:10000:5000' >/etc/subgid
RUN setcap cap_setuid+ep /usr/bin/newuidmap
RUN setcap cap_setgid+ep /usr/bin/newgidmap
ENTRYPOINT /bin/bash"

# ----------------
# function section
# ----------------

function build_image () {

	## -b	build dev environment image

	# copy user content from current environment
	# ~/.bashrc for prompt
	# ~/.ssh for git keys
	# ~/.config/nvim for custom nvim configurations
	mkdir -p containers/upload/.config
	cp -Rp ~/.bashrc ~/.ssh containers/upload/.
	cp -Rp ~/.config/nvim containers/upload/.config/.
	date > containers/upload/build
	rm -f containers/upload/.config/nvim/lazy-lock.json

	echo ----------------------------------------
	echo generating container build configuration
	echo ----------------------------------------

	# initialize containerfile
	echo "$CONTAINER_CONFIG" | tee containers/Containerfile

	echo ------------------------
	echo building container image
	echo ------------------------

	mkdir -p ${HOME_DIRECTORY} &> /dev/null
	podman build \
	--tag ${IMAGE_NAME} \
	--volume ${HOME_DIRECTORY}:/home \
	--security-opt label=disable \
	--security-opt unmask=/proc/* \
	--security-opt seccomp=unconfined \
	containers
	rm -rf containers/upload

}

function deploy_container () {

	## -d	deploy container based on dev image

	echo -----------------
	echo running container
	echo -----------------

	# pre-flight checks
	mkdir -p ${WORK_DIRECTORY} &> /dev/null
	podman unshare chown -R ${USER_UID}:${USER_GID} ${HOME_DIRECTORY}/${USER_NAME} ${WORK_DIRECTORY}

	# start container if it exists - otherwise create it
	if ($(podman inspect ${CONTAINER_NAME} &> /dev/null)); then

		podman start ${CONTAINER_NAME}

	else

		podman run \
		--detach \
		--tty \
		--security-opt label=disable \
		--security-opt unmask=/proc/* \
		--security-opt seccomp=unconfined \
		--network host \
		--user ${USER_NAME} \
		--device /dev/fuse \
		--name ${CONTAINER_NAME} \
		--volume ${HOME_DIRECTORY}:/home \
		--volume ${WORK_DIRECTORY}:/home/${USER_NAME}/${CONTAINER_NAME} \
		--hostname ${CONTAINER_NAME} \
		--env TERM=${TERM} \
		--workdir /home/${USER_NAME} \
		localhost/${IMAGE_NAME}:latest

	fi

	# connect to the running container
	podman attach ${CONTAINER_NAME}

}

function show_help () {

	## -h	show help

	echo
	echo "Build and/or deploy a containerized development environment"
	echo
	echo "Usage: ${0} [OPTION]"
	echo
	grep \#\# "${0}" | sed 's/##//' | grep -v grep
	echo

}

# ----------------------
# command line arguments
# ----------------------

while getopts ":bdh" OPT; do

	case ${OPT} in

		b) # build image
			build_image
			exit
			;;

		d) # deploy container
			deploy_container
			exit
			;;

		h) # show help
			show_help
			exit
			;;

		\?)
			show_help
			echo "Invalid option: $OPTARG"
			exit
			;;

		:)
			show_help
			echo "Missing argument: $OPTARG requires an argument"
			exit
			;;

	esac

done
