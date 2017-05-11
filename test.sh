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
	git rm --cached -r $(test $2 && echo $2 || echo path/to/sub/) -q >/dev/null 2>&1
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

say '# (empty git repo with empty subdirectory)'
rm -rf test-repo
git init test-repo $QUIET
cd test-repo
mkdir -p path/to/sub/

say
say '###'
say "# Let's say we have history like so:"
add_and_commit 'a Main thing' a-Main-thing
add_and_commit 'a Sub thing' path/to/sub/a-Sub-thing
add_and_commit 'another Sub thing' path/to/sub/another-Sub-thing
add_and_commit 'another Main thing' another-Main-thing
test $QUIET || git log --graph --oneline --decorate --stat

say
say '###'
say '# We can split out the commit history of just Sub in path/to/sub/:'
../git-subhistory.sh split path/to/sub/ -v $QUIET
assert_is_subcommit_of SPLIT_HEAD master^
assert_is_subcommit_of SPLIT_HEAD^ master^^

say
say '# (or with a branch name)'
../git-subhistory.sh split path/to/sub/ -b subproj -v $QUIET
test $QUIET || git log --graph --oneline --decorate --stat --all
assert_is_subcommit_of subproj master^
assert_is_subcommit_of subproj^ master^^
# TODO: make sure SPLIT_HEAD is not a symref to subproj

say
say '# (also try split from not toplevel of repo)'
cd path/to/sub/
../../../../git-subhistory.sh split . -v $QUIET
assert_is_subcommit_of SPLIT_HEAD master^
assert_is_subcommit_of SPLIT_HEAD^ master^^
cd ../../../

say
say '###'
say "# Now say we pull in upstream bugfixes:"
git checkout subproj -q
add_and_commit 'fix Sub somehow' fix-Sub-somehow 'Fix Sub somehow'
add_and_commit 'fix Sub further' fix-Sub-further 'Fix Sub further'
git checkout - -q
test $QUIET || git log --graph --oneline --decorate --stat subproj

say
say '###'
say '# Finally, we can assimilate these changes back into Main:'
../git-subhistory.sh assimilate path/to/sub/ subproj -v $QUIET
assert_is_subcommit_of subproj ASSIMILATE_HEAD
assert_is_subcommit_of subproj^ ASSIMILATE_HEAD^
assert "rest of assimilated tree is the same as when diverged from master" \
	$(rest_of_tree ASSIMILATE_HEAD) = $(rest_of_tree master^)

git merge ASSIMILATE_HEAD -m "Merge subhistory branch 'subproj' under path/to/sub/" $QUIET
assert "successful merge" $? = 0
assert "rest of merged tree is the same as before" \
	$(rest_of_tree master) = $(rest_of_tree master^)

test $QUIET || git log --graph --oneline --decorate --stat

say
say '###'
say '# Also try assimilating in a new subproject that had never been split:'
git checkout --orphan new-subproj -q
git reset --hard
add_and_commit 'a NewSub thing' a-NewSub-thing
add_and_commit 'another NewSub thing' another-NewSub-thing
git checkout master -q
mkdir -p path/to/new-sub/
../git-subhistory.sh assimilate path/to/new-sub/ new-subproj -v $QUIET
assert_is_subcommit_of new-subproj ASSIMILATE_HEAD path/to/new-sub/
assert_is_subcommit_of new-subproj^ ASSIMILATE_HEAD^ path/to/new-sub/

git merge --allow-unrelated-histories ASSIMILATE_HEAD -m "Merge subhistory branch 'new-subproj' under path/to/new-sub/" $QUIET
assert "successful merge" $? = 0
assert "rest of merged tree is the same as before" \
	$(rest_of_tree master path/to/new-sub/) = $(rest_of_tree master^ path/to/new-sub/)

say
say '###'
say "# Assimilating merge commits with the same Main tree, keep it"
git checkout subproj -q
git branch other-subproj
add_and_commit 'extend Sub somehow' extend-Sub-somehow 'Extend Sub somehow'
git checkout other-subproj -q
add_and_commit 'extend Sub some-other-how' extend-Sub-some-other-how 'Extend Sub some-other-how'
git checkout subproj -q
git merge other-subproj -m "Merge branch 'other-subproj' into subproj" -q
git checkout master -q
../git-subhistory.sh assimilate path/to/sub/ subproj -v $QUIET
assert_is_subcommit_of subproj ASSIMILATE_HEAD
assert "rest of assimilated tree is the same as when diverged from master" \
	$(rest_of_tree ASSIMILATE_HEAD) = $(rest_of_tree $(git merge-base ASSIMILATE_HEAD master^))

git merge ASSIMILATE_HEAD -m "Merge subhistory branch 'subproj' under path/to/sub/" $QUIET
assert "successful merge" $? = 0
assert "rest of merged tree is the same as before" \
	$(rest_of_tree master) = $(rest_of_tree master^)

say
say '###'
say '# Assimilating merge commits with Main trees with one common descendant, use descendant'
add_and_commit 'yet another Main thing' yet-another-Main-thing
add_and_commit 'yet another Sub thing' path/to/sub/yet-another-Sub-thing
add_and_commit 'a Main thing after split diverges' a-Main-thing-after-split-diverges
../git-subhistory.sh split path/to/sub/ -b yet-more-subproj -v $QUIET
git checkout subproj -q
git merge yet-more-subproj -m "Merge branch 'yet-more-subproj' into subproj" $QUIET
add_and_commit 'yet more Sub fixes' yet-more-Sub-fixes
git checkout - -q

../git-subhistory.sh assimilate path/to/sub/ subproj -v $QUIET
assert_is_subcommit_of subproj ASSIMILATE_HEAD
assert "rest of assimilated tree is the same as when diverged from master" \
	$(rest_of_tree ASSIMILATE_HEAD) = $(rest_of_tree master^)

git merge ASSIMILATE_HEAD -m "Merge subhistory branch 'subproj' under path/to/sub/" $QUIET
assert "successful merge" $? = 0
assert "rest of merged tree is the same as before" \
	$(rest_of_tree master) = $(rest_of_tree master@{1})

say
say '###'
say '# Assimilating merge commits with independent Main trees, use HEAD'
git checkout -b indep -q
add_and_commit 'independent Main thing' independent-Main-thing
add_and_commit 'Sub thing after independent Main thing' path/to/sub/Sub-thing-after-independent-Main-thing
../git-subhistory.sh split path/to/sub/ -b subproj-indep -v $QUIET
git checkout - -q
add_and_commit 'master Main thing' master-Main-thing
add_and_commit 'Sub thing after master Main thing' path/to/sub/Sub-thing-after-master-Main-thing
../git-subhistory.sh split path/to/sub/ -B subproj -v $QUIET
git checkout subproj -q
git merge subproj-indep -m "Merge branch 'subproj-indep' into subproj" $QUIET
git checkout - -q

../git-subhistory.sh assimilate path/to/sub/ subproj -v $QUIET
assert_is_subcommit_of subproj ASSIMILATE_HEAD
assert "rest of assimilated tree is the same as HEAD" \
	$(rest_of_tree ASSIMILATE_HEAD) = $(rest_of_tree HEAD)

git merge ASSIMILATE_HEAD --ff-only $QUIET
assert "successful merge" $? = 0
assert "rest of merged tree is the same as before" \
	$(rest_of_tree master) = $(rest_of_tree master@{1})



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
