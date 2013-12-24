#!/bin/sh

case "$1" in
	-s|--summary|--summarize) QUIET=-q; say () { :; } ;;
	*) QUIET=; say () { echo "$@"; } ;;
esac

asserts_count=0
fails_count=0

assert () {
	asserts_count=$(($asserts_count + 1))
	msg="$1"
	shift
	test "$@" || {
		fails_count=$(($fails_count + 1))
		echo "!!! Failed Assert: $msg"
	}
}

say '0. setup empty git repo, empty folders'
rm -rf test-repo
git init test-repo $QUIET
cd test-repo

mkdir -p path/to/sub/

say
say '1. create and add foo in Sub, commit to Main'
echo foo > path/to/sub/foo
git add path/to/sub/foo
git commit -m 'Add path/to/sub/foo' $QUIET

say
if test $fails_count = 0
then
	echo "All $asserts_count tests pass"
else
	echo "$fails_count tests failed (out of $asserts_count)"
fi
exit $fails_count
