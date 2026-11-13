#!/bin/bash
set -e
RES=android/app/src/main/res
cp -r resources/android-res/* $RES/
find $RES -name 'splash.png' -exec cp resources/splash.png {} \;
sed -i 's#<application#<uses-permission android:name="android.permission.USE_BIOMETRIC" />\n    <application#' android/app/src/main/AndroidManifest.xml
G=android/app/build.gradle
sed -i "s/versionCode [0-9]*/versionCode ${GITHUB_RUN_NUMBER:-1}/; s/versionName \".*\"/versionName \"$(cat VERSION)\"/" $G
sed -i 's#<application#<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n    <application#' android/app/src/main/AndroidManifest.xml
grep -q sirius.keystore $G || sed -i '0,/^android {/s#^android {#android {\n    signingConfigs {\n        debug {\n            storeFile file("../../sirius.keystore")\n            storePassword "sirius123"\n            keyAlias "sirius"\n            keyPassword "sirius123"\n        }\n    }#' $G
echo "patched"
