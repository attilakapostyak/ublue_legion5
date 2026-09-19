# Build images
podman build -t fedora_base ./fedora_base/
podman build -t fedora_main ./fedora_main/

# Assemble using distrobox.ini configuration
distrobox assemble rm
distrobox assemble create

