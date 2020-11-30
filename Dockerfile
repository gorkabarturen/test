# Author: Sergio Paracuellos <sparacuellos@ikergune.com>

# In any directory on the docker host, perform the following actions:
#   * Copy this Dockerfile in the directory.
#   * Create input and output directories: mkdir -p yocto/output yocto/input
#   * Build the Docker image with the following command:
#     docker build --ssh priv=$HOME/.ssh/id_rsa --no-cache \
#            --build-arg "host_uid=$(id -u)" --build-arg "host_gid=$(id -g)" --build-arg "USER_NAME=$USERNAME" \
#            --add-host ELETSRVGIT.etxe-tar.local:192.168.230.21 --tag "ainguraiiot-oberonx-image:latest" .
#   * Run the Docker image, which in turn runs the Yocto and which produces all artifacts for oberonx,
#     with the following command:
#     docker run -it --rm --add-host ELETSRVGIT.etxe-tar.local:192.168.230.21 \
#            -v /opt/Xilinx:/opt/Xilinx:ro \
#            -v -v /etc/localtime:/etc/localtime:ro \
#            -v -v /etc/timezone:/etc/timezone:ro \
#            -v /opt/yocto/zynqmp/download:/opt/yocto/zynqmp/download \
#            -v /opt/yocto/zynqmp/sstate-cache:/opt/yocto/zynqmp/sstate-cache \
#            -v $PWD/yocto/output:/home/ainguraiiot/yocto/output \
#            -v /var/artifacts:/var/artifacts \
#            ainguraiiot-oberonx-image:latest
#

# Use Ubuntu 18.04 LTS as the basis for the Docker image.
FROM ubuntu:18.04

# Install all the Linux packages required for Yocto builds. Note that the packages python3,
# tar, locales and cpio are not listed in the official Yocto documentation. The build, however,
# without them.
RUN apt-get update && apt-get -y install openssh-client gawk wget git-core diffstat unzip texinfo gcc-multilib \
    build-essential chrpath socat cpio python python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping libsdl1.2-dev xterm tar locales xvfb libgtk2.0-0 bc tmux libncurses5-dev \
    vim tmux

# By default, Ubuntu uses dash as an alias for sh. Dash does not support the source command
# needed for setting up the build environment in CMD. Use bash as an alias for sh.
RUN rm /bin/sh && ln -s bash /bin/sh

# Set the locale to en_US.UTF-8, because the Yocto build fails without any locale set.
RUN locale-gen en_US.UTF-8 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

ARG USER_NAME

# The running container writes all the build artefacts to a host directory (outside the container).
# The container can only write files to host directories, if it uses the same user ID and
# group ID owning the host directories. The host_uid and group_uid are passed to the docker build
# command with the --build-arg option. By default, they are both 1001. The docker image creates
# a group with host_gid and a user with host_uid and adds the user to the group. The symbolic
# name of the group and user is ainguraiiot
ARG host_uid
ARG host_gid

RUN groupadd -g $host_gid $USER_NAME && useradd -g $host_gid -m -s /bin/bash -u $host_uid $USER_NAME

# Make sure ssh get the properly configured key
RUN echo "IdentityFile ~/.ssh/id_rsa" >> /etc/ssh/ssh_config

# Create downloads and sstate dirs, will be shared from host on real runs
RUN mkdir -p /opt/yocto/zynqmp/download && chown $USER_NAME.$USER_NAME /opt/yocto/zynqmp/download
RUN mkdir -p /opt/yocto/zynqmp/sstate-cache && chown $USER_NAME.$USER_NAME /opt/yocto/zynqmp/sstate-cache

# Create directory to store artifacts copied with 'copy_artifacts.sh' script. This directory
# will be shared from host on runs and should have $USER_NAME owner
ENV ARTIFACTS_STORE_DIR /var/artifacts
RUN mkdir -p $ARTIFACTS_STORE_DIR

# Perform the Yocto build as user ainguraiiot (not as root).
# NOTE: The USER command does not set the environment variable HOME.
# By default, docker runs as root. However, Yocto builds should not be run as root, but as a 
# normal user. Hence, we switch to the newly created user ainguraiiot.
USER $USER_NAME

# Create the directory structure for the Yocto build in the container. The lowest two directory
# levels must be the same as on the host.
ENV BUILD_INPUT_DIR /home/$USER_NAME/yocto/input
ENV BUILD_OUTPUT_DIR /home/$USER_NAME/yocto/output
RUN mkdir -p $BUILD_INPUT_DIR $BUILD_OUTPUT_DIR

# Configure git user and email
#RUN git config --global user.name "Ainguraiiot CI"
#RUN git config --global user.email cicd@ainguraiiot.com

# This is necessary to prevent the "git clone" operation from failing
# with an "unknown host key" error.
#RUN mkdir -m 700 /home/$USER_NAME/.ssh; \
#    touch /home/$USER_NAME/.ssh/known_hosts; \
#    chmod 600 /home/$USER_NAME/.ssh/known_hosts; \
#    ssh-keyscan github.com > /home/$USER_NAME/.ssh/known_hosts; \
#    ssh-keyscan ELETSRVGIT.etxe-tar.local >> /home/$USER_NAME/.ssh/known_hosts

# Put keys into correct folder
#RUN echo "${ssh_prv_key}" > /home/$USER_NAME/.ssh/id_rsa && \
#    echo "${ssh_pub_key}" > /home/$USER_NAME/.ssh/id_rsa.pub && \
#    chmod 600 /home/$USER_NAME/.ssh/id_rsa && \
#    chmod 600 /home/$USER_NAME/.ssh/id_rsa.pub

# Put swupdate pwd into correct file
#RUN echo "${swupdate_pwd}" > /home/$USER_NAME/.swupdate_priv_pwd && \
#    chmod 400 /home/$USER_NAME/.swupdate_priv_pwd

# Clone the tools repositories in $BUILD_INPUT_DIR
#WORKDIR $BUILD_INPUT_DIR
#RUN git clone git@ELETSRVGIT.etxe-tar.local:ainguraiiot/tools.git

# Prepare the yocto's environment using prepare_environment.sh script
#WORKDIR $BUILD_INPUT_DIR/tools/yocto
#RUN ./prepare_environment.sh workspace

# Fix xvfb-run for use with Xilinx xsct
# xvfb-run needs to know about terminfo for some operations. I don't really know if this is strictly necessary, but it gets rid of some errors
USER root
RUN rm -fr /usr/share/terminfo && ln -sf /lib/terminfo /usr/share/terminfo
USER $USER_NAME

# This only will be executed for runs
#WORKDIR $BUILD_OUTPUT_DIR
#CMD rm -rf build; cp -r $BUILD_INPUT_DIR/tools/yocto/workspace/build . ; \
#    echo "EXTRA_IMAGE_FEATURES += \"debug-tweaks\"" >> build/conf/local.conf && \
#    echo "GIT_URL: $GIT_URL" && echo "GIT_BRANCH: $GIT_BRANCH" && echo "TARGET_BRANCH: $TARGET_BRANCH" && echo "GIT_COMMIT: $GIT_COMMIT" && \
#    source $BUILD_INPUT_DIR/tools/yocto/workspace/poky/oe-init-build-env && \
#    xvfb-run --server-args=":0.0 -ac" bitbake fsbl && \
#    bitbake arm-trusted-firmware u-boot-1st-stage pmu-firmware && \
#    xvfb-run --server-args=":0.0 -ac" bitbake oberonx-image && bitbake oberonx-ramdisk && bitbake oberonx-image -c populate_sdk && \
#    $BUILD_INPUT_DIR/tools/ci/scripts/copy_artifacts_ci.sh $BUILD_INPUT_DIR/tools/yocto $BUILD_OUTPUT_DIR/build $ARTIFACTS_STORE_DIR/$TARGET_BRANCH $GIT_URL $GIT_BRANCH $GIT_COMMIT && \
#    rm -rf $BUILD_OUTPUT_DIR/build

CMD tmux
