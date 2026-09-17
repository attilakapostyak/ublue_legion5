FROM fedora-toolbox:42

ARG NODE_VERSION=24

# Install NVM
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
ENV NVM_DIR=/root/.nvm
# install node
RUN bash -c "source $NVM_DIR/nvm.sh && nvm install $NODE_VERSION"

# RUN npm install -g @fission-ai/openspec@latest

