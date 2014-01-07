#!/bin/sh
# http://github.com/laughinghan/git-subhistory

# util fn (at the top 'cos used in options parsing)
die () {
	echo "fatal:" "$@" >&2
	exit 1
}

######################
# Options Parsing
#   >:( so many lines

# if zero args, default to -h
test $# = 0 && set -- -h

OPTS_SPEC="\
git-subhistory split <subproj-path> (-b | -B) <subproj-branch>
git-subhistory merge <subproj-path> <subproj-branch>
--
q,quiet         be quiet
v,verbose       be verbose
h               show the help

 options for 'split':
b=              create a new branch for the split-out commit history
B=              like -b but force creation"

eval "$(echo "$OPTS_SPEC" | git rev-parse --parseopt -- "$@" || echo exit $?)"
# ^ this is actually what you're supposed to do, see `git rev-parse --help`

quiet="$GIT_QUIET"
verbose=
newbranch=
force_newbranch=

while test $# != 0
do
	case "$1" in
	-q|--quiet) quiet=1 ;;
	--no-quiet) quiet= ;;
	-v|--verbose) verbose=1 ;;
	--no-verbose) verbose= ;;
	-b|-B)
		test "$1" = "-B" && force_newbranch=-f
		shift
		newbranch="$1"
		test "$newbranch" || die "branch name must be nonempty"
	;;
	--) break ;;
	esac
	shift
done
shift

##############
# Logging Fns

if test "$quiet"
then
	say () {
		:
	}
	say_stdin () {
		cat >/dev/null
	}
else
	say () {
		echo "$@" >&2
	}
	say_stdin () {
		cat >&2
	}
fi

if test "$verbose" -a ! "$quiet"
then
	elaborate () {
		echo "$@" >&2
	}
else
	elaborate () {
		:
	}
fi

usage () {
	echo "$@" >&2
	echo >&2
	exec "$0" -h
}

##############
# Subcommands

# TODO: find a better place to put this
commit_filter='git commit-tree "$@"' # default/noop

subhistory_split () {
	test $# = 0 || usage "wrong number of arguments to 'split'"

	elaborate "'split' path_to_sub='$path_to_sub' newbranch='$newbranch'" \
		"force_newbranch='$force_newbranch'"

	# setup SPLIT_HEAD
	if test "$newbranch"
	then
		git branch "$newbranch" $force_newbranch || exit $?
		split_head="$(git rev-parse --symbolic-full-name "$newbranch")"
		git symbolic-ref SPLIT_HEAD "$split_head" || exit $?
		elaborate "Created/reset branch $newbranch (symref-ed as SPLIT_HEAD)"
	else
		git update-ref --no-deref SPLIT_HEAD HEAD || exit $?
		elaborate "Set detached SPLIT_HEAD"
	fi

	git filter-branch \
		--original subhistory-tmp/filter-branch-backup \
		--subdirectory-filter "$path_to_sub" \
		--commit-filter "$commit_filter" \
		-- SPLIT_HEAD \
		2>&1 | say_stdin || exit $?

	git update-ref --no-deref SPLIT_HEAD SPLIT_HEAD || exit $?
	elaborate 'un-symref-ed SPLIT_HEAD'

	say
	say "Split out history of $path_to_sub to $(
		if test "$newbranch"
		then
			echo "$newbranch (also SPLIT_HEAD)"
		else
			echo "SPLIT_HEAD"
		fi
	)"
}

subhistory_merge () {
	# args
	test $# = 1 || usage "wrong number of arguments to 'merge'"
	merge_from="$1"
	git update-ref SUBHISTORY_MERGE_HEAD "$merge_from" || exit $?

	elaborate "'merge' path_to_sub='$path_to_sub' merge_from='$merge_from'" \
		"SUBHISTORY_MERGE_HEAD='$(git rev-parse SUBHISTORY_MERGE_HEAD)'"

	# split HEAD
	mkdir "$tmp_dir/split-to-orig-map" || exit $?
	commit_filter='
		rewritten=$(git commit-tree "$@") &&
		tmp_dir="$(git rev-parse --git-dir)/subhistory-tmp" &&
		echo $GIT_COMMIT > "$tmp_dir/split-to-orig-map/$rewritten" &&
		echo $rewritten'
	subhistory_split || exit $?
	say # blank line after summary of subhistory_split

	# build the synthetic commits on top of the original Main commits, by
	# filtering for parents that were splits and swapping them out for their
	# originals
	parent_filter='
		tmp_dir="$(git rev-parse --git-dir)/subhistory-tmp" &&
		set -- $(cat) &&
		while test $# != 0
		do
			printf -- "-p %s " \
				$(cat "$tmp_dir/split-to-orig-map/$2" 2>/dev/null || echo $2) &&
			shift 2
		done'

	# write synthetic commits that make the same changes as the Sub commits but
	# to the subtree of Main, by rewriting each Sub commit as having the same tree
	# as either the original Main commit the Sub commit's parent was split from or
	# the new synthetic parent commit that's been rewritten as a Main commit, but
	# with the subtree overwritten.
	# - Complication: there can be >1 parent, with different Main trees. Luckily,
	#   differences in Main trees could only possibly come from Main commits that
	#   are ancestors of HEAD [Footnote], which must have been merged at some
	#   point in the history of HEAD, since HEAD itself is a single commit.
	#   Finding the earliest such merge that won't conflict with HEAD is
	#   nontrivial, since the same two commits could be merged in any number of
	#   commits with any tree at all. Leave finding the earliest merged tree as
	#   TODO, for now just use HEAD, which is guaranteed not to merge conflict
	#   with itself.
	#   + [Footnote]: others weren't split into ancestors of SPLIT_HEAD, and hence
	#     aren't in the split-to-orig-map, and thus couldn't be a rewritten
	#     parent. This is actually why merge explicitly doesn't invert splitting
	#     of all commits, it only inverts splitting of ancestors of HEAD.
	index_filter='
		tmp_dir="$(git rev-parse --git-dir)/subhistory-tmp" &&
		if git rev-parse --verify -q $GIT_COMMIT^2 # if $GIT_COMMIT is a merge
		then
			Main_tree=HEAD # TODO: find earliest merged tree
		else
			parent=$(git rev-parse $GIT_COMMIT^) &&
			Main_tree=$(cat "$tmp_dir/split-to-orig-map/$parent" 2>/dev/null \
				|| map $parent)
		fi &&
		git read-tree $Main_tree &&
		git rm --cached -r '"'$path_to_sub'"' -q &&
		git read-tree --prefix='"'$path_to_sub'"' $GIT_COMMIT'

	git filter-branch \
		--original subhistory-tmp/filter-branch-backup \
		--parent-filter "$parent_filter" \
		--index-filter "$index_filter"  \
		-- SPLIT_HEAD..SUBHISTORY_MERGE_HEAD \
		2>&1 | say_stdin || exit $?

	# TODO: non-fast-foward merges' default commit messages should mention the
	# $merge_from branchname rather than all be
	#     Merge commit 'SUBHISTORY_MERGE_HEAD' into <current-branchname>
	# charming though that may be
	git merge SUBHISTORY_MERGE_HEAD
}

#######
# Main

subcommand="$1"
shift

case "$subcommand" in
	split|merge) ;;
	*) usage "unknown subcommand '$subcommand'" ;;
esac

# All subcommands need:

# "path/to/sub/" (relative to toplevel) from <subproj-path> (relative to current
# working directory); bonus: normalize away .'s and //'s, guarantee trailing /
path_to_sub="$(cd "$1" && git rev-parse --show-prefix)" || exit $?
shift

# to be at toplevel (for filter-branch); need ./ in case of empty string
cd ./$(git rev-parse --show-cdup) || exit $?

# a temporary directory for e.g. filter-branch backups
tmp_dir="$(git rev-parse --git-dir)/subhistory-tmp"
mkdir "$tmp_dir" || exit $?

"subhistory_$subcommand" "$@"

rm -rf "$tmp_dir"
