#!/bin/bash

set -ouex pipefail

just apps-install
just distrobox-build