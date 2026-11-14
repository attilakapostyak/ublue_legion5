# Build context: files needed only while building, never copied into the image.
FROM scratch AS ctx
COPY build_files /
COPY cosign.pub /cosign.pub

# Base image: Aurora (KDE Plasma) + developer tools + open NVIDIA driver.
# Images: https://github.com/orgs/ublue-os/packages
FROM ghcr.io/ublue-os/aurora-dx-nvidia-open:stable

# All customizations live in build_files/build.sh.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Fail the build if the result isn't a valid bootc image.
RUN bootc container lint
