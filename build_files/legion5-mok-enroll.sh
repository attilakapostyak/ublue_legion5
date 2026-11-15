#!/bin/bash
# Runs at every boot (legion5-mok-enroll.service).
#
# With Secure Boot on, the NVIDIA driver only loads if the Universal Blue
# signing key is enrolled in the firmware. This queues the key for enrolment
# when it isn't, so the firmware asks for confirmation on the next reboot:
# "Enroll MOK" -> Continue -> Yes, password "universalblue". The firmware
# requires that a person confirms; it can't be automated further.
#
# Does nothing when Secure Boot is off, the key is enrolled, or it's already
# queued.

set -euo pipefail

key=/etc/pki/akmods/certs/akmods-ublue.der
password=universalblue

if [[ "$(mokutil --sb-state 2>/dev/null || true)" != *enabled* ]]; then
    echo "Secure Boot is off, no key needed."
    exit 0
fi

# mokutil exits 1 in several of these cases, so look at its output
state="$(mokutil --test-key "$key" 2>/dev/null || true)"
case "$state" in
    *"already enrolled"*)
        echo "Key is enrolled."
        exit 0
        ;;
    *"enrollment request"*)
        echo "Key is queued; confirm it on the blue MOK screen at the next reboot (password: $password)."
        exit 0
        ;;
esac

# Wait for input on the MOK screen instead of timing out after 10 seconds
mokutil --timeout -1
printf '%s\n%s\n' "$password" "$password" | mokutil --import "$key"
echo "Key queued. At the next reboot choose Enroll MOK -> Continue -> Yes, password: $password"
