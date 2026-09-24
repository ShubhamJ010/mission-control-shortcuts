#!/bin/zsh

# Reset Accessibility approval status for MCSC (Bundle ID: sj010.MCSC)
# This eliminates the need to manually remove MCSC with the "-" button in System Settings.

BUNDLE_ID="sj010.MCSC"

echo "Resetting macOS Accessibility permission for ${BUNDLE_ID}..."
tccutil reset Accessibility "${BUNDLE_ID}" || true
echo "Done. When you run MCSC, macOS will prompt for permission fresh."
