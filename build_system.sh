# Build image locally
# sudo podman build -t ublue_legion5 .

# Switch to the new image
# sudo bootc switch --transport containers-storage --no-signature-verification localhost/kans_silverblue:latest


# Build toolbox images
# Build development
cd ./toolbox_images/development
./build.sh

