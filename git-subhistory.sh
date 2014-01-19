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

# TODO: find a better place to put this
# Get "path/to/sub/" (relative to toplevel) from <subproj-path> (relative to
# original current working directory).
# Bonus: assimilate needs .'s and //'s normalized away, trailing / guaranteed
get_path_to_sub () {
	test "$1" || usage "first arg <subproj-path> is required (just . is allowed)"
	path_to_sub="$(cd "./$GIT_PREFIX/$1" && git rev-parse --show-prefix)" || exit $?
}

##############
# Subcommands

# TODO: find a better place to put this
commit_filter='git commit-tree "$@"' # default/noop

subhistory_split () {
	test $# = 1 || usage "wrong number of arguments to 'split'"
	get_path_to_sub "$1"

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

subhistory_assimilate () {
	# args
	test $# = 2 || usage "wrong number of arguments to '$subcommand'"
	get_path_to_sub "$1" # FIXME requires path/to/sub/ to already exist :(
	assimilatee="$2"
	git update-ref ASSIMILATE_HEAD "$assimilatee" || exit $?

	elaborate "'assimilate' path_to_sub='$path_to_sub' assimilatee='$assimilatee'" \
		"ASSIMILATE_HEAD='$(git rev-parse ASSIMILATE_HEAD)'"

	# test if "path/to/sub/" has git history yet
	if test "$(git ls-tree --name-only HEAD "${path_to_sub%/}")"
	then
		# split HEAD
		mkdir "$GIT_DIR/subhistory-tmp/split-to-orig-map" || exit $?
		commit_filter='
			rewritten=$(git commit-tree "$@") &&
			echo $GIT_COMMIT > "$GIT_DIR/subhistory-tmp/split-to-orig-map/$rewritten" &&
			echo $rewritten'
		subhistory_split "$1" || exit $?
		say # blank line after summary of subhistory_split

		# build the synthetic commits on top of the original Main commits, by
		# filtering for parents that were splits and swapping them out for their
		# originals
		parent_filter='
			for parent in $(cat)
			do
				test $parent != -p \
				&& cat "$GIT_DIR/subhistory-tmp/split-to-orig-map/$parent" 2>/dev/null \
				|| echo $parent
			done'

		# write synthetic commits that make the same changes as the Sub commits but
		# to the subtree of Main, by rewriting each Sub commit as having the same tree
		# as either the original Main commit the Sub commit's parent was split from or
		# the new synthetic parent commit that's been rewritten as a Main commit, but
		# with the subtree overwritten.
		# - Complication: there can be >1 parent, with different Main trees. Luckily,
		#   differences in Main trees could only possibly come from Main commits that
		#   are ancestors of HEAD [FN1], which must have been merged at some point in
		#   the history of HEAD, since HEAD itself is a single commit. Finding the
		#   earliest such merge that won't conflict with HEAD is nontrivial, since the
		#   same two commits could be merged in any number of commits with any tree at
		#   all. Leave finding the earliest merged tree as TODO, for now if all parent
		#   Main trees are the same use that [FN2], otherwise just use HEAD, which is
		#   guaranteed not to merge conflict with itself.
		#   + [FN1]: others weren't split into ancestors of SPLIT_HEAD, and hence
		#     aren't in the split-to-orig-map, and thus couldn't be a rewritten
		#     parent. This is actually why merge explicitly doesn't invert splitting
		#     of all commits, it only inverts splitting of ancestors of HEAD.
		#   + [FN2]: augh, this takes more than a dozen lines: looping over each
		#     parent, read the tree for the (rewritten) parent into the index, delete
		#     "path/to/sub/" from the index, and then if this is the first parent,
		#     set a variable to the hash of the index, else check that the hash of
		#     the index matches the stored hash (bail out defaulting to HEAD if not).
		index_filter='
			if git rev-parse --verify -q $GIT_COMMIT^2 >/dev/null # if this is a merge
			then
				for parent in $(git rev-list --no-walk --parents $GIT_COMMIT \
					| cut -f 2- -d " ") # first word is just $GIT_COMMIT
				do
					git read-tree $(
						cat "$GIT_DIR/subhistory-tmp/split-to-orig-map/$parent" 2>/dev/null \
						|| map $parent) &&
					git rm --cached -r '"'$path_to_sub'"' -q &&
					if test -z $parent_Main_tree
					then
						parent_Main_tree=$(git write-tree)
					elif test $(git write-tree) != $parent_Main_tree
					then
						git read-tree HEAD && # TODO: find earliest merged tree
						git rm --cached -r '"'$path_to_sub'"' -q &&
						break
					fi
				done
			else
				parent=$(git rev-parse $GIT_COMMIT^) &&
				git read-tree $(
					cat "$GIT_DIR/subhistory-tmp/split-to-orig-map/$parent" 2>/dev/null \
					|| map $parent)
				git rm --cached -r '"'$path_to_sub'"' -q
			fi &&
			git read-tree --prefix='"'$path_to_sub'"' $GIT_COMMIT'

		revs_to_rewrite=SPLIT_HEAD..ASSIMILATE_HEAD
	else
		parent_filter=
		index_filter='
			git read-tree --empty &&
			git read-tree --prefix='"'$path_to_sub'"' $GIT_COMMIT'

		revs_to_rewrite=ASSIMILATE_HEAD
	fi

	git filter-branch \
		--original subhistory-tmp/filter-branch-backup \
		--parent-filter "$parent_filter" \
		--index-filter "$index_filter"  \
		-- $revs_to_rewrite \
	2>&1 | say_stdin || exit $?

	say
	say "Assimilated $assimilatee into $(
		git symbolic-ref --short HEAD -q \
		|| echo "detached HEAD ($(git rev-parse --short HEAD))"
	) under $path_to_sub as ASSIMILATE_HEAD"
}

subhistory_merge () {
	mkdir -p "./$GIT_PREFIX/$1" &&
	subhistory_assimilate "$@" &&
	say &&
	git merge ASSIMILATE_HEAD --edit -m "$(
		echo "$(merge_name "$merge_from" | git fmt-merge-msg \
			| sed 's/^Merge /Merge subhistory /') under $path_to_sub"
	)" \
	2>&1 | say_stdin
}

# # # # # #
# Util Fn, only used in one place, whose functionality really should be part of
# a git utility but isn't, and had to be copied from the git source code.

# As part of generating merge commit messages, belongs in fmt-merge-msg, but
# had to be copied from contrib/examples/git-merge.sh (latest master branch):
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
	split|assimilate|merge) ;;
	*) usage "unknown subcommand '$subcommand'" ;;
esac

# All subcommands need:

# the original current working directory prefix (named like for git aliases)
GIT_PREFIX="$(git rev-parse --show-prefix)"

# to be at toplevel (for filter-branch); need ./ in case of empty string
cd ./$(git rev-parse --show-cdup) || exit $?

# the path to the .git directory (or directory to use as such)
GIT_DIR="$(git rev-parse --git-dir)"

# a temporary directory for e.g. filter-branch backups
mkdir "$GIT_DIR/subhistory-tmp/" || exit $?
trap "rm -rf '$GIT_DIR/subhistory-tmp/'" EXIT

"subhistory_$subcommand" "$@"
