ARG image_user=amd64
ARG image_repo=debian
ARG image_tag=buster
ARG VHOME_SUFFIX
ARG INSTANCE_NAME

FROM ${image_user}/${image_repo}:${image_tag} as volttron_base

SHELL [ "bash", "-c" ]

ENV OS_TYPE=debian
ENV DIST=buster
ENV VOLTTRON_GIT_BRANCH=rabbitmq-volttron
ENV VOLTTRON_USER_HOME=/home/volttron
ARG VHOME_SUFFIX
#ENV VOLTTRON_HOME=${VOLTTRON_USER_HOME}/.volttron
ENV VOLTTRON_HOME=${VOLTTRON_USER_HOME}/${VHOME_SUFFIX}
ENV CODE_ROOT=/code
ENV VOLTTRON_ROOT=${CODE_ROOT}/volttron
ENV VOLTTRON_USER=volttron
ENV USER_PIP_BIN=${VOLTTRON_USER_HOME}/.local/bin
ENV RMQ_ROOT=${VOLTTRON_USER_HOME}/rabbitmq_server
ENV RMQ_HOME=${RMQ_ROOT}/rabbitmq_server-3.7.7
ARG INSTANCE_NAME
ENV INSTANCE_NAME=${INSTANCE_NAME}

# --no-install-recommends \
USER root
RUN set -eux; apt-get update; apt-get install -y --no-install-recommends \
    procps \
    gosu \
    vim \
    tree \
    build-essential \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    openssl \
    libssl-dev \
    libevent-dev \
    git \
    gnupg \
    dirmngr \
    apt-transport-https \
    wget \
    curl \
    ca-certificates \
    libffi-dev \
    acl \
    sudo


RUN id -u $VOLTTRON_USER &>/dev/null || adduser --disabled-password --gecos "" $VOLTTRON_USER

RUN mkdir -p /code && chown $VOLTTRON_USER.$VOLTTRON_USER /code \
  && echo "export PATH=/home/volttron/.local/bin:$PATH" > /home/volttron/.bashrc

############################################
# ENDING volttron_base image
############################################

FROM volttron_base AS volttron_core

# Note I couldn't get variable expansion on the chown argument to work here
# so must hard code the user.  Note this is a feature request for docker
# https://github.com/moby/moby/issues/35018
# COPY --chown=volttron:volttron . ${VOLTTRON_ROOT}

RUN ln -s /usr/bin/pip3 /usr/bin/pip

USER $VOLTTRON_USER

# The following lines ar no longer necesary because of the copy command above.
#WORKDIR /code
#RUN git clone https://github.com/VOLTTRON/volttron -b ${VOLTTRON_GIT_BRANCH}
COPY --chown=volttron:volttron volttron /code/volttron

WORKDIR /code/volttron
RUN pip3 install -e . --user
RUN echo "package installed at `date`"

############################################
# RABBITMQ SPECIFIC INSTALLATION
############################################
USER root
RUN ./scripts/rabbit_dependencies.sh $OS_TYPE $DIST

RUN mkdir -p /startup $VOLTTRON_HOME && \
    chown $VOLTTRON_USER.$VOLTTRON_USER $VOLTTRON_HOME
COPY ./core/entrypoint.sh /startup/entrypoint.sh
COPY ./core/bootstart.sh /startup/bootstart.sh
COPY ./core/setup-platform.py /startup/setup-platform.py
RUN chmod +x /startup/*

USER $VOLTTRON_USER
RUN mkdir $RMQ_ROOT
RUN set -eux \
    && wget -P $VOLTTRON_USER_HOME https://github.com/rabbitmq/rabbitmq-server/releases/download/v3.7.7/rabbitmq-server-generic-unix-3.7.7.tar.xz \
    && tar -xf $VOLTTRON_USER_HOME/rabbitmq-server-generic-unix-3.7.7.tar.xz --directory $RMQ_ROOT \
    && $RMQ_HOME/sbin/rabbitmq-plugins enable rabbitmq_management rabbitmq_federation rabbitmq_federation_management rabbitmq_shovel rabbitmq_shovel_management rabbitmq_auth_mechanism_ssl rabbitmq_trust_store
############################################


############################################
# ADD VOLTTRON_USER TO SUDOERS TO SUPPORT SECURE USERMODE
############################################
USER root
RUN echo "Adding Permissions to sudoers for user: $VOLTTRON_USER"
RUN echo "${VOLTTRON_USER} ALL= NOPASSWD: /usr/sbin/groupadd volttron_${INSTANCE_NAME}" | EDITOR='tee --append' visudo --file=/etc/sudoers.d/volttron_${INSTANCE_NAME}
# "root" is hardcoded and added to the voltrron_<instance name> group
RUN echo "${VOLTTRON_USER} ALL= NOPASSWD: /usr/sbin/usermod -a -G volttron_${INSTANCE_NAME} root" | EDITOR='tee --append' visudo --file=/etc/sudoers.d/volttron_${INSTANCE_NAME}
# allow user to add and delete users using the volttron agent user pattern
RUN echo "${VOLTTRON_USER} ALL= NOPASSWD: /usr/sbin/useradd volttron_[1-9]* -r -G volttron_${INSTANCE_NAME}" | EDITOR='tee --append' visudo --file=/etc/sudoers.d/volttron_${INSTANCE_NAME}
RUN echo "${VOLTTRON_USER} ALL= NOPASSWD: /usr/sbin/userdel volttron_[1-9]*" | EDITOR='tee --append' visudo --file=/etc/sudoers.d/volttron_${INSTANCE_NAME}
# allow user to run all non-sudo commands for all volttron agent users
RUN echo "${VOLTTRON_USER} ALL=(%volttron_${INSTANCE_NAME}) NOPASSWD: ALL" | EDITOR='tee --append' visudo --file=/etc/sudoers.d/volttron_${INSTANCE_NAME}
RUN echo "Permissions set for ${VOLTTRON_USER}"
RUN echo "Volttron secure mode setup is complete"

# TODO: give volttron_user access to secure_stop_agent.sh in /code/volttron/scripts
#RUN script=${BASH_SOURCE[0]} && \
#script=`realpath $script`
#source_dir=$(dirname "$(dirname "$script")")
# RUN echo "$volttron_user ALL= NOPASSWD: $source_dir/scripts/secure_stop_agent.sh volttron_[1-9]* [1-9]*" | EDITOR='tee --append' visudo --file=/etc/sudoers.d/volttron_${INSTANCE_NAME}
############################################


########################################
# The following lines should be run from any Dockerfile that
# is inheriting from this one as this will make the volttron
# run in the proper location.
#
# The user must be root at this point to allow gosu to work
########################################
USER root
WORKDIR ${VOLTTRON_USER_HOME}
ENTRYPOINT ["/startup/entrypoint.sh"]
CMD ["/startup/bootstart.sh"]


