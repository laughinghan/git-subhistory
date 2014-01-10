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
		for parent
		do
			test $parent != -p \
			&& cat "$tmp_dir/split-to-orig-map/$parent" 2>/dev/null \
			|| echo $parent
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

	say
	git merge SUBHISTORY_MERGE_HEAD --edit -m "$(
		echo "$(merge_name "$merge_from" | git fmt-merge-msg \
			| sed 's/^Merge /Merge subhistory /') under $path_to_sub"
	)" \
	2>&1 | say_stdin
}

# # # # # #
# Util Fn, only used in one place, whose functionality really should be part of
# a git utility but isn't, and had to be copied from the git source code.

# As part of generating merge commit messages, belongs in fmt-merge-msg, but
# had to be copied from contrib/examples/git-merge.sh (latest master branch).
# Only modification: doesn't expect global var $GIT_DIR.
# https://github.com/git/git/blob/932f7e47699993de0f6ad2af92be613994e40afe/contrib/examples/git-merge.sh#L140-L171
merge_name () {
	remote="$1"
	rh=$(git rev-parse --verify "$remote^0" 2>/dev/null) || return
	if truname=$(expr "$remote" : '\(.*\)~[0-9]*$') &&
		git show-ref -q --verify "refs/heads/$truname" 2>/dev/null
	then
		echo "$rh		branch '$truname' (early part) of ."
		return
	fi
	if found_ref=$(git rev-parse --symbolic-full-name --verify \
							"$remote" 2>/dev/null)
	then
		expanded=$(git check-ref-format --branch "$remote") ||
			exit
		if test "${found_ref#refs/heads/}" != "$found_ref"
		then
			echo "$rh		branch '$expanded' of ."
			return
		elif test "${found_ref#refs/remotes/}" != "$found_ref"
		then
			echo "$rh		remote branch '$expanded' of ."
			return
		fi
	fi
	GIT_DIR="$(git rev-parse --git-dir)"
	if test "$remote" = "FETCH_HEAD" -a -r "$GIT_DIR/FETCH_HEAD"
	then
		sed -e 's/	not-for-merge	/		/' -e 1q \
			"$GIT_DIR/FETCH_HEAD"
		return
	fi
	echo "$rh		commit '$remote'"
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
