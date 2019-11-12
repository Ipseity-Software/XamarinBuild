#!/usr/local/bin/bash
function exit_error() {
	echo "$1"
	touch /tmp/buildfail
	exit 1
}
function build_failure() {
	echo "##### BUILD FAILURE #####"
	echo "removing ios build"
	mv $IOS/Info.plist.bak $IOS/Info.plist
	mv $DROID/Properties/AndroidManifest.xml.bak $DROID/Properties/AndroidManifest.xml
	rm -rf $XCAR
	rm -f $CFG_OUT_IOS/archive/$NBUILD-$VER.tar
	rm -f $CFG_OUT_IOS/$NBUILD-$VER.ipa
	sleep 5
	exit_error ""
}
START=`date`
DIR=`pwd`
IOS="$DIR/$CFG_PROJ_COM/$CFG_PROJ_COM.iOS"
DROID="$DIR/$CFG_PROJ_COM/$CFG_PROJ_COM.Android"
VER=$1
NBUILD=$2
BTYPE=$3

# BEGIN DEPENDENCY CHECK #
source "xamarinbuild.conf"
if [ -z "$CFG_LOADED" ]; then
	echo "ERROR! No configuration present"
	exit 1
else #check configuration
	if 	[ -z "$CFG_PROJ_IOS" ] &&
		[ -z "$CFG_PROJ_DROID" ]; then
		echo "Will not build, no iOS or Android targets defined"
		exit 2
	fi
	if [ ! -z "$CFG_PROJ_IOS" ]; then
		if 	[ -z "$CFG_IPA_USR" ] ||
			[ -z "$CFG_IPA_TEAM" ] ||
			[ -z "$CFG_IPA_PROFILE" ] ||
			[ -z "$CFG_IPA_DISTRIB" ]; then
			echo "Cannot build for iOS, missing configuration"
			exit 2
		fi
	fi
	if 	[ "$CFG_SUBMIT_IOS" -eq "1" ]
		if [ -z "$CFG_PROJ_IOS" ]; then
			echo "Cannot submit iOS if it won't be built"
			exit 2
		fi
		if [ -z "$CFG_IPA_KEY" ]; then
			echo "Cannot submit iOS without the IPA key"
			exit 2
		fi
	fi
	if [ ! -z "$CFG_PROJ_DROID" ]; then
		if	[ -z "$CFG_APK_STR" ] ||
			[ -z "$CFG_APK_ALS" ] ||
			[ -z "$CFG_APK_KEY" ]; then
			echo "Cannot build for Android, missing configuration"
			exit 2
		fi
	fi
fi
hash bc || exit_error "bc is not installed and is required"
python <<< "from oauth2client.service_account import ServiceAccountCredentials" 2>&1 /dev/null || exit_error "cannot import oauthclient"
python <<< "from oauth2client.client import AccessTokenRefreshError" 2>&1 /dev/null || exit_error "cannot import oauthclient"
python <<< "from apiclient.discovery import build" 2>&1 /dev/null || exit_error "cannot import apiclient.discovery"
python <<< "import json" 2>&1 /dev/null || exit_error "cannot import json"
python <<< "import httplib2" 2>&1 /dev/null || exit_error "cannot import httplib2"
python <<< "import argparse" 2>&1 /dev/null || exit_error "cannot import argparse"
if 	[ ! -f "$SYS_ALTOOL" ] &&
	[ ! -z "$CFG_PROJ_IOS" ]; then
	exit_error "altool not found in $SYS_ALTOOL"
fi
if [ ! -z "$CFG_PROJ_DROID" ]; then
	if [ ! -f "$SYS_ANDROID_TOOLS/zipalign" ]; then
		exit_error "zipalign not found in $SYS_ANDROID_TOOLS"
	fi
	if [ ! -f "$SYS_ANDROID_TOOLS/apksigner" ]; then
		exit_error "apksigner not found in $SYS_ANDROID_TOOLS"
	fi
fi
if 	[ ! -z "$CFG_ARTIFACT_USR" ] &&
	[ ! -z "$CFG_ARTIFACT_URI" ] &&
	[ ! -z "$CFG_ARTIFACT_FLDR" ]; then
	ssh $CFG_ARTIFACT_USR@$CFG_ARTIFACT_URI "exit 0" || exit_error "not authorized on artifact server, cannot continue"
	DO_ARTIFACT_UPLOAD="yes"
fi
# END DEPENDENCY CHECK #

echo "Build type is $BTYPE"
echo "Cleaning Release"
msbuild $CFG_SLN /t:$CFG_PROJ_COM:clean /p:Configuration=Release > /dev/null 2>&1
msbuild $CFG_SLN /t:$CFG_PROJ_IOS:clean /p:Configuration=Release > /dev/null 2>&1
msbuild $CFG_SLN /t:$CFG_PROJ_DROID:clean /p:Configuration=Release > /dev/null 2>&1
echo "Cleaning Debug"
msbuild $CFG_SLN /t:$CFG_PROJ_COM:clean /p:Configuration=Debug > /dev/null 2>&1
msbuild $CFG_SLN /t:$CFG_PROJ_IOS:clean /p:Configuration=Debug > /dev/null 2>&1
msbuild $CFG_SLN /t:$CFG_PROJ_DROID:clean /p:Configuration=Debug > /dev/null 2>&1
if [ "$BTYPE" != "Release" ] ; then
	echo "Cleaning $BTYPE"
	msbuild $CFG_SLN /t:$CFG_PROJ_COM:clean /p:Configuration=$BTYPE > /dev/null 2>&1
	msbuild $CFG_SLN /t:$CFG_PROJ_IOS:clean /p:Configuration=$BTYPE > /dev/null 2>&1
	msbuild $CFG_SLN /t:$CFG_PROJ_DROID:clean /p:Configuration=$BTYPE > /dev/null 2>&1
fi

if [ ! -z "$CFG_PROJ_IOS" ]; then
echo "Configuring iOS"
cp $IOS/Info.plist $IOS/Info.plist.bak
defaults write $IOS/Info CFBundleShortVersionString "$VER"		#version
defaults write $IOS/Info CFBundleVersion "$NBUILD"

echo "Building iOS"
	if [ "$BTYPE" == "Release" ] ; then
		if msbuild $CFG_SLN /p:Configuration=Release /p:Platform=iPhone /p:ArchiveOnBuild=true /t:$CFG_PROJ_IOS /v:q ; then
			echo "Build successful"
		else
			build_failure
		fi
	else
		if msbuild $CFG_SLN /p:Configuration=$BTYPE /p:ArchiveOnBuild=true /t:$CFG_PROJ_IOS /v:q ; then
			echo "Build successful"
		else
			build_failure
		fi
	fi
	echo "Cleaning up iOS"
	mv $IOS/Info.plist.bak $IOS/Info.plist

	FLDR=~/Library/Developer/Xcode/Archives/`date +%F`
	XCAR=`ls -t $FLDR | grep "$CFG_PROJ_COM.iOS" | head -n 1`
	mkdir -p $CFG_OUT_IOS/archive
	tar -cf $CFG_OUT_IOS/archive/$NBUILD-$VER.tar "$FLDR/$XCAR" > /dev/null 2>&1

	echo "Building IPA"
	rm -f /tmp/exportoptions.plist
	echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" > /tmp/exportoptions.plist
	echo "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">" >> /tmp/exportoptions.plist
	echo "<plist version=\"1.0\">" >> /tmp/exportoptions.plist
	echo "<dict>" >> /tmp/exportoptions.plist
	echo " <key>method</key>" >> /tmp/exportoptions.plist
	echo " <string>app-store</string>" >> /tmp/exportoptions.plist
	echo " <key>teamID</key>" >> /tmp/exportoptions.plist
	echo " <string>$CFG_IPA_TEAM</string>" >> /tmp/exportoptions.plist
	echo " <key>uploadBitcode</key>" >> /tmp/exportoptions.plist
	echo " <true/>" >> /tmp/exportoptions.plist
	echo " <key>compileBitcode</key>" >> /tmp/exportoptions.plist
	echo " <true/>" >> /tmp/exportoptions.plist
	echo " <key>uploadSymbols</key>" >> /tmp/exportoptions.plist
	echo " <true/>" >> /tmp/exportoptions.plist
	echo " <key>signingStyle</key>" >> /tmp/exportoptions.plist
	echo " <string>manual</string>" >> /tmp/exportoptions.plist
	echo " <key>signingCertificate</key>" >> /tmp/exportoptions.plist
	echo " <string>$CFG_IPA_PROFILE</string>" >> /tmp/exportoptions.plist
	echo " <key>provisioningProfiles</key>" >> /tmp/exportoptions.plist
	echo " <dict>" >> /tmp/exportoptions.plist
	echo "  <key>$CFG_PACKAGE_IDENTIFIER</key>" >> /tmp/exportoptions.plist
	echo "  <string>$CFG_IPA_DISTRIB</string>" >> /tmp/exportoptions.plist
	echo " </dict>" >> /tmp/exportoptions.plist
	echo "</dict>" >> /tmp/exportoptions.plist
	echo "</plist>" >> /tmp/exportoptions.plist
	mkdir -p /tmp/ipa
	rm -f /tmp/ipa/*.ipa
	xcodebuild -exportArchive -archivePath "$FLDR/$XCAR" -exportOptionsPlist /tmp/exportoptions.plist -exportPath /tmp/ipa || build_failure
	mkdir -p $CFG_OUT_IOS
	mv /tmp/ipa/*.ipa $CFG_OUT_IOS/$NBUILD-$VER.ipa
	DID_IOS_BUILD="yes"
fi

if [ ! -z "$CFG_PROJ_DROID" ]; then
	echo "Configuring Android"
	cp $DROID/Properties/AndroidManifest.xml $DROID/Properties/AndroidManifest.xml.bak
	LINES=`cat $DROID/Properties/AndroidManifest.xml | wc -l | sed -e 's/^[[:space:]]*//'`
	NTAIL=`echo "$LINES - 1" | bc -i | tail -n 1 | sed 's/\n//g'`
	MFST=`cat $DROID/Properties/AndroidManifest.xml | tail -n $NTAIL`
	echo "<?xml version=\"1.0\" encoding=\"utf-8\"?>" > $DROID/Properties/AndroidManifest.xml
	echo "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" android:versionName=\"$VER\" package=\"$CFG_PACKAGE_IDENTIFIER\" android:versionCode=\"$NBUILD\">" >> $DROID/Properties/AndroidManifest.xml
	echo $MFST >> $DROID/Properties/AndroidManifest.xml #write manifest payload

	echo "Building Android"
	if msbuild $CFG_SLN /p:Configuration=$BTYPE /p:ArchiveOnBuild=true /p:AndroidKeyStore=true /p:AndroidSigningKeyAlias=$CFG_APK_ALS /p:AndroidSigningKeyPass=$CFG_APK_KEY \
		/p:AndroidSigningKeyStore=$CFG_APK_STR /p:AndroidSigningStorePass=$CFG_APK_KEY /t:$CFG_PROJ_DROID:SignAndroidPackage /v:q ; then
		echo "Build successful"
	else
		echo "Build failed, trying again"
		if msbuild $CFG_SLN /p:Configuration=$BTYPE /p:ArchiveOnBuild=true /p:AndroidKeyStore=true /p:AndroidSigningKeyAlias=$CFG_APK_ALS /p:AndroidSigningKeyPass=$CFG_APK_KEY \
			/p:AndroidSigningKeyStore=$CFG_APK_STR /p:AndroidSigningStorePass=$CFG_APK_KEY /t:$CFG_PROJ_DROID:SignAndroidPackage /v:q ; then
			echo "Build successful"
		else
			build_failure
		fi
	fi

	echo "Signing Android"
	cp $DROID/bin/$BTYPE/$CFG_PACKAGE_IDENTIFIER.apk /tmp/android.apk
	$SYS_ANDROID_TOOLS/zipalign -f -v 4 /tmp/android.apk /tmp/aligned.apk > /dev/null 2>&1
	$SYS_ANDROID_TOOLS/apksigner sign --ks $CFG_APK_STR --ks-pass pass:$CFG_APK_KEY -ks-key-alias $CFG_APK_ALS /tmp/aligned.apk > /dev/null 2>&1

	echo "Cleaning up Android"
	mkdir -p $CFG_OUT_AND
	cp /tmp/aligned.apk $CFG_OUT_AND/$NBUILD-$VER.apk
	mv $DROID/Properties/AndroidManifest.xml.bak $DROID/Properties/AndroidManifest.xml
	DID_ANDROID_BUILD="yes"
fi

if [ ! -z "$DO_ARTIFACT_UPLOAD" ]; then
	if [ ! -z "$DID_ANDROID_BUILD" ]; then
		echo "Uploading Android APK"
		scp $CFG_OUT_AND/$NBUILD-$VER.apk "${CFG_ARTIFACT_USR}@${CFG_ARTIFACT_URI}:${CFG_ARTIFACT_FLDR}/android/$VER-${NBUILD}.apk"
	fi
	if [ ! -z "$DID_IOS_BUILD" ]; then
		echo "Compressing iOS Archive (this will take a while)"
		lzma -9 -e $CFG_OUT_IOS/archive/$NBUILD-$VER.tar
		echo "Uploading iOS Archive"
		scp $CFG_OUT_IOS/archive/$NBUILD-$VER.tar.lzma "${CFG_ARTIFACT_USR}@${CFG_ARTIFACT_URI}:${CFG_ARTIFACT_FLDR}/ios/$VER-${NBUILD}.tar.lzma"
	fi
fi

if 	[ ! -z "$CFG_IPA_USR" ] &&
	[ ! -z "$CFG_IPA_KEY" ] &&
	[ ! -z "$DID_IOS_BUILD" ] &&
	[ "$CFG_SUBMIT_IOS" -eq "1" ]; then
	echo "Submitting iOS IPA"
	rm -f /tmp/altool # just in case
	ln -s "$SYS_ALTOOL" /tmp/altool
	/tmp/altool --upload-app -f $CFG_OUT_IOS/$NBUILD-$VER.ipa -u "$CFG_IPA_USR" -p "$CFG_IPA_KEY"
	rm -f /tmp/altool # clean up our mess
fi

if 	[ -f apkuploader.json ] &&
	[ ! -z "$DID_ANDROID_BUILD" ] &&
	[ "$CFG_SUBMIT_ANDROID" -eq "1" ]; then
	echo "Submitting Android APK"
	./apkupload.py -p $CFG_PACKAGE_IDENTIFIER -a $CFG_OUT_AND/$NBUILD-$VER.apk -s apkuploader.json
fi

if 	[ ! -z "$CFG_TEST_PROJECT" ] &&
	[ ! -z "$CFG_TEST_IDENTIFIER" ] &&
	[ ! -z "$CFG_TEST_SIMID" ]; then
	echo "Running Unit Tests"
	./simulator.sh "$NBUILD"
fi

ENDED=`date`
echo "Started: $START"
echo "Ended  : $ENDED"
echo "## COMPLETE ##"
exit 0
