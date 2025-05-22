#!/bin/env bash

# ---------------------
# configuration section
# ---------------------

CONTAINER_NAME=laboratory
IMAGE_NAME=development
USER_NAME=developer
USER_UID=1000
USER_GID=1000
WORK_DIRECTORY=${HOME}/repository/${CONTAINER_NAME}

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
COPY .bashrc /home/${USER_NAME}/.
COPY .ssh/ /home/${USER_NAME}/.ssh/.
COPY nvim/ /home/${USER_NAME}/.config/nvim
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

	# copy custom user from current environment
	# ~/.ssh for git keys
	# ~/.config/nvim for custom nvim configurations
	cp -Rp ~/.bashrc ~/.ssh ~/.config/nvim containers/.
	rm -f containers/nvim/lazy-lock.json

	echo ----------------------------------------
	echo generating container build configuration
	echo ----------------------------------------

	# initialize containerfile
	echo "$CONTAINER_CONFIG" | tee containers/Containerfile

	echo ------------------------
	echo building container image
	echo ------------------------

	podman build -t "$IMAGE_NAME" containers
	rm -rf containers/.bashrc containers/.ssh containers/nvim

}

function deploy_container () {

	## -d	deploy container based on dev image

	echo -----------------
	echo running container
	echo -----------------

	# pre-flight checks
	mkdir -p ${WORK_DIRECTORY} &> /dev/null
	podman unshare chown -R ${USER_UID}:${USER_GID} ${WORK_DIRECTORY}

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
		--volume ${WORK_DIRECTORY}:/home/${USER_NAME}/${CONTAINER_NAME} \
		--hostname ${CONTAINER_NAME} \
		--env TERM=xterm-256color \
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
