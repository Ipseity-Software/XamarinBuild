source "xamarinbuild.conf"
if [ -z "$CFG_LOADED" ]; then
	echo "ERROR! No configuration present"
	exit 1
fi
CFG_PROJ_BASE=`pwd`
if msbuild $CFG_SLN /p:Configuration=Release /p:Platform=iPhoneSimulator /t:$CFG_TEST_PROJECT /v:q ; then
	echo "Build successful"
else
	echo "Unable to build tests"
	exit 1
fi
while [ 1 -eq 1 ]; do
	result=`xcrun simctl boot $CFG_TEST_SIMID 2>&1 >/dev/null | grep "Unable" | wc -l | sed 's/       //g'`
	if [ "$result" -eq "1" ]; then break; fi
	sleep 2
done
xcrun simctl install $CFG_TEST_SIMID $CFG_PROJ_BASE/$CFG_TEST_PROJECT/bin/iPhoneSimulator/Release/$CFG_TEST_PROJECT.app
rm -f /tmp/output
nc -l 1234 > /tmp/output &
sleep 1
xcrun simctl launch $CFG_TEST_SIMID $CFG_TEST_IDENTIFIER
while [ 1 -eq 1 ]; do
	result=`ps -ax | grep "nc -l 1234" | wc -l | sed 's/       //g'`
	if [ "$result" -eq "2" ]; then sleep 5; continue; fi
	break;
done
echo "Done"
xcrun simctl shutdown $CFG_TEST_SIMID
good=`cat /tmp/output | grep "FAIL" | wc -l | sed 's/       //g'`
if [ ! "$good" -eq "0" ]; then
	echo "Oh no! failed tests!"
	echo
	if	[ ! -z "$CFG_ARTIFACT_USR" ] &&
		[ ! -z "$CFG_ARTIFACT_URI" ] &&
		[ ! -z "$CFG_ARTIFACT_FLDR" ]; then
		scp /tmp/output "${CFG_ARTIFACT_USR}@${CFG_ARTIFACT_URI}:${CFG_ARTIFACT_FLDR}/tests/$1.txt"
	else
		cat /tmp/output
	fi
else
	echo "All good"
fi
