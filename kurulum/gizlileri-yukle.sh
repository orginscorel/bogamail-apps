#!/bin/bash
# GitHub Actions gizlilerini bir kez yükler. Kullanım: bash kurulum/gizlileri-yukle.sh sahip/depo
# Token: /root/.config/bogamail-apps/gh-token (Contents, Workflows, Secrets, Actions: Read and write).
set -e
D=/root/.config/bogamail-apps
REPO=${1:?sahip/depo}
GH_TOKEN_FILE=${GH_TOKEN_FILE:-$D/gh-token} $D/gizli "$REPO" \
  ASC_KEY_P8=$D/AuthKey_5Z9AN85989.p8 \
  IOS_P12_B64=$D/ios-imza/dagitim.p12:b64 IOS_P12_PASS=$D/ios-imza/p12.sifre \
  MAC_APP_P12_B64=$D/mac-imza/app.p12:b64 MAC_INST_P12_B64=$D/mac-imza/inst.p12:b64 MAC_P12_PASS=$D/mac-imza/p12.sifre \
  ANDROID_KEYSTORE_B64=$D/android/bogamail.p12:b64 ANDROID_KEYSTORE_PASS=$D/android/parola
