# Introduction
My own README.md 

# Installation

You can start with any Fedora ublue variants. Clone this repository, make sure the OS Image is built and then switch to the new image

After reboot using the new image, execute the following command to install everything:
```
install.sh
```

# Cheat Sheet
1. Build new OS image: 
    1. Modify /Containerfile
    1. Modify /build_files/build.sh. This is where all the installations happen during image build
    1. Commit changes
    1. Wait for Github to finish the build
    1. execute command:
    ```
    sudo bootc switch <new image>
    ```
    1. Reboot machine
1. Build ditrobox images:
```
just distrobox-build
```


# Distrobox
For now only Fedora based images are customized. All should be based on fedora_base image

Settings for each box can be defined in /distrobox/distrobox.ini


