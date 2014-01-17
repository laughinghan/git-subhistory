#!/bin/sh

##################
# Options Parsing

case "$1" in
	-s|--summary|--summarize) QUIET=-q; say () { :; } ;;
	*) QUIET=; say () { echo "$@"; } ;;
esac

####################
# Testing Framework

asserts_count=0
fails_count=0

assert () {
	asserts_count=$(($asserts_count + 1))
	msg="$1"
	shift
	if test "$@"
	then
		say "Assert: $msg"
	else
		fails_count=$(($fails_count + 1))
		echo "!!! Failed Assert: $msg"
	fi
}

#########
# Utils: commit_non_hash_info(), assert_is_subcommit_of(), rest_of_tree(), add_and_commit()

commit_non_hash_info () {
	git log $1 --no-walk --pretty='format:%an%n%ae%n%ai%n%cn%n%ce%n%ci%n%B'
}

assert_is_subcommit_of () {
	assert "tree of $1 matches subtree of $2" \
		$(git rev-parse $1:) = $(git rev-parse $2:$(test $3 && echo $3 || echo path/to/sub/))
	assert "$1 commit other info matches $2" \
	"$(commit_non_hash_info $1)" = "$(commit_non_hash_info $2)"
}

rest_of_tree () (
	export GIT_INDEX_FILE=.git/index.tmp
	git read-tree $1
	git rm --cached -r path/to/sub/ -q
	git write-tree
	rm .git/index.tmp
)

add_and_commit () {
	echo "$1" > $2
	git add $2
	git commit -m "$(test "$3" && echo "$3" || echo "Add $1")" -q
}

#######
# Main

say '(empty git repo with empty subdirectory)'
rm -rf test-repo
git init test-repo $QUIET
cd test-repo
mkdir -p path/to/sub/

say
say "Let's say we have history like so:"
add_and_commit 'a Main thing' a-Main-thing
add_and_commit 'a Sub thing' path/to/sub/a-Sub-thing
add_and_commit 'another Sub thing' path/to/sub/another-Sub-thing
add_and_commit 'another Main thing' another-Main-thing
test $QUIET || git log --graph --oneline --decorate --stat

say
say 'We can split out the commit history of just Sub in path/to/sub/:'
../git-subhistory.sh split path/to/sub/ -v $QUIET
assert_is_subcommit_of SPLIT_HEAD master^
assert_is_subcommit_of SPLIT_HEAD^ master^^

say
say '(or with branch name)'
../git-subhistory.sh split path/to/sub/ -b subproj -v $QUIET
test $QUIET || git log --graph --oneline --decorate --stat --all
assert_is_subcommit_of subproj master^
assert_is_subcommit_of subproj^ master^^
# TODO: make sure SPLIT_HEAD is not a symref to subproj

say
say '(also try split from not toplevel of repo)'
cd path/to/sub/
../../../../git-subhistory.sh split . -v $QUIET
assert_is_subcommit_of SPLIT_HEAD master^
assert_is_subcommit_of SPLIT_HEAD^ master^^
cd ../../../

say
say "Say we pull in upstream bugfixes:"
git checkout subproj -q
add_and_commit 'fix Sub somehow' fix-Sub-somehow 'Fix Sub somehow'
add_and_commit 'fix Sub further' fix-Sub-further 'Fix Sub further'
git checkout - -q
test $QUIET || git log --graph --oneline --decorate --stat subproj

say
say 'Assimilate these changes back into Main:'
../git-subhistory.sh assimilate path/to/sub/ subproj -v $QUIET
test $QUIET || git log --graph --oneline --decorate --stat
assert_is_subcommit_of subproj ASSIMILATE_HEAD
assert_is_subcommit_of subproj^ ASSIMILATE_HEAD^
assert "rest of tree on subproj is the same as before on master" \
	$(rest_of_tree ASSIMILATE_HEAD) = $(rest_of_tree master^)

say
say 'Now try assimilating in a new subproject that had never been split:'
git checkout --orphan new-subproj -q
git reset --hard
add_and_commit 'a NewSub thing' a-NewSub-thing
add_and_commit 'another NewSub thing' another-NewSub-thing
git checkout - -q
mkdir -p path/to/new-sub/
../git-subhistory.sh assimilate path/to/new-sub/ new-subproj -v $QUIET
assert_is_subcommit_of new-subproj ASSIMILATE_HEAD path/to/new-sub/
assert_is_subcommit_of new-subproj^ ASSIMILATE_HEAD^ path/to/new-sub/


###############
# Test Summary

say
if test $fails_count = 0
then
	echo "All $asserts_count tests pass"
else
	echo "$fails_count tests failed (out of $asserts_count)"
fi
exit $fails_count
