FROM fedora-toolbox:42

ARG NODE_VERSION=24

RUN dnf install -y btop

# Install NVM
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
ENV NVM_DIR=/root/.nvm
# install node
RUN bash -c "source $NVM_DIR/nvm.sh && nvm install $NODE_VERSION"

RUN curl -fsSL https://opencode.ai/install | bash

# RUN npm install -g @fission-ai/openspec@latest

RUN curl -fsSL https://claude.ai/install.sh | bash

