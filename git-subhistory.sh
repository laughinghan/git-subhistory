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
	die "'$subcommand' not yet implemented"
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
