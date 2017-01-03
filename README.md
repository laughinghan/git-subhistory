`git-subhistory` &mdash; Interchangeably merge in and split out subtree history

by Han <laughinghan@gmail.com>

### Introduction

`git-subhistory`, like `git-submodule` and `git-subtree`, manages
subprojects (call one "Sub") in a superproject (call it "Main") git
repo. Like `git-subtree` but unlike `git-submodule`, `git-subhistory` is
stateless, you pass "Sub's" subdirectory (call it `path/to/sub/`) as an
argument to `git-subhistory` but it's not specially marked in any way,
"Sub's" files are tracked directly by the "Main" repo like any other
files, and no other git tools know or care that `path/to/sub/` contains
a subproject.

### Wait but what does this _do_?

Well, you know how you can `git log path/to/sub/` to see the history
of just stuff in `path/to/sub/`? `git-subhistory split` (and
`git-subtree split`) is like that but creates a whole new commit history
of just that stuff, rooted inside `path/to/sub/`. This new commit
history of just "Sub" can be `git push`-ed to its own repo and developed
independently, or included in other projects.

Say that happens and commits are made on top of that new commit history.
Then `git-subhistory merge` merges those changes back into "Main's"
commit history by inverting `split`, creating new commits making those
same changes on top of the original "Main" commits, then merging them.
(Contrast `git-subtree merge`, which merges the changes correctly, but
messes up the commit graph with duplicate commits.)

### Example

Let's say we have history like so:

                                                                                                    [HEAD]
    [initial commit]                                                                                [master]
    o-------------------------------o-------------------------------o-------------------------------o
    Add a Main thing                Add a Sub thing                 Add another Sub thing           Add another Main thing
     __________________________      __________________________      __________________________      __________________________
    |                          |    |                          |    |                          |    |                          |
    |  Files:                  |    |  Files:                  |    |  Files:                  |    |  Files:                  |
    |  + a-Main-thing          |    |    a-Main-thing          |    |    a-Main-thing          |    |    a-Main-thing          |
    |                          |    |  + path/to/sub/          |    |    path/to/sub/          |    |  + another-Main-thing    |
    |                          |    |  +   a-Sub-thing         |    |      a-Sub-thing         |    |    path/to/sub/          |
    |                          |    |                          |    |  +   another-Sub-thing   |    |      a-Sub-thing         |
    |                          |    |                          |    |                          |    |      another-Sub-thing   |
    |                          |    |                          |    |                          |    |                          |
    |__________________________|    |__________________________|    |__________________________|    |__________________________|

We can split out the commit history of just Sub in `path/to/sub/`:

    $ ../git-subhistory.sh split path/to/sub/ -b subproj
    Rewrite 6285d3c68b3eb5f0cd2cb8c376c0d83a0f2b7c0a (2/2)
    Ref 'refs/heads/subproj' was rewritten

    Split out history of path/to/sub/ to subproj (also SPLIT_HEAD)

We now have 2 disconnected histories, the untouched `master` branch, and
a new `subproj` branch, with the history of just the stuff inside
`path/to/sub/`:

                                                                                                    [HEAD]
    [initial commit]                                                                                [master]
    o-------------------------------o-------------------------------o-------------------------------o
    Add a Main thing                Add a Sub thing                 Add another Sub thing           Add another Main thing
     __________________________      __________________________      __________________________      __________________________
    |                          |    |                          |    |                          |    |                          |
    |  Files:                  |    |  Files:                  |    |  Files:                  |    |  Files:                  |
    |  + a-Main-thing          |    |    a-Main-thing          |    |    a-Main-thing          |    |    a-Main-thing          |
    |                          |    |  + path/to/sub/          |    |    path/to/sub/          |    |  + another-Main-thing    |
    |                          |    |  +   a-Sub-thing         |    |      a-Sub-thing         |    |    path/to/sub/          |
    |                          |    |                          |    |  +   another-Sub-thing   |    |      a-Sub-thing         |
    |                          |    |                          |    |                          |    |      another-Sub-thing   |
    |                          |    |                          |    |                          |    |                          |
    |__________________________|    |__________________________|    |__________________________|    |__________________________|

                                    [SPLIT_HEAD]
    [initial commit]                [subproj]
    o-------------------------------o
    Add a Sub thing                 Add another Sub thing
     __________________________      __________________________
    |                          |    |                          |
    |  Files:                  |    |  Files:                  |
    |  + a-Sub-thing           |    |    a-Sub-thing           |
    |                          |    |  + another-Sub-thing     |
    |                          |    |                          |
    |                          |    |                          |
    |__________________________|    |__________________________|

Say we push `subproj` to a public repo for just Sub, and implausibly,
our code isn't perfect and bugfixes are contributed to the public repo.
Now we've `git pull`-ed in upstream bugfixes:

                                                                                                    [sub-upstream/master]  # remote-tracking branch
    [initial commit]                                                                                [subproj]
    o-------------------------------o-------------------------------o-------------------------------o
    Add a Sub thing                 Add another Sub thing           Fix Sub somehow                 Fix Sub further
     __________________________      __________________________      __________________________      __________________________
    |                          |    |                          |    |                          |    |                          |
    |  Files:                  |    |  Files:                  |    |  Files:                  |    |  Files:                  |
    |  + a-Sub-thing           |    |    a-Sub-thing           |    |    a-Sub-thing           |    |    a-Sub-thing           |
    |                          |    |  + another-Sub-thing     |    |    another-Sub-thing     |    |    another-Sub-thing     |
    |                          |    |                          |    |  + fix-Sub-somehow       |    |    fix-Sub-somehow       |
    |                          |    |                          |    |                          |    |  + fix-Sub-further       |
    |                          |    |                          |    |                          |    |                          |
    |__________________________|    |__________________________|    |__________________________|    |__________________________|

Here's where the magic happens: we can easily merge these changes into
Main **using the `Add another Sub thing` commit as the merge base**:

    $ ../git-subhistory.sh merge path/to/sub/ subproj
    Rewrite 6285d3c68b3eb5f0cd2cb8c376c0d83a0f2b7c0a (2/2)
    Ref 'SPLIT_HEAD' was rewritten

    Split out history of path/to/sub/ to SPLIT_HEAD

    Rewrite d535a7c1c90b42d66eb0938172538aa5fc878460 (2/2)
    Ref 'ASSIMILATE_HEAD' was rewritten

    Merge made by the 'recursive' strategy.
     path/to/sub/fix-Sub-further | 1 +
     path/to/sub/fix-Sub-somehow | 1 +
     2 files changed, 2 insertions(+)
     create mode 100644 path/to/sub/fix-Sub-further
     create mode 100644 path/to/sub/fix-Sub-somehow

Now the history of `master` looks like:

                                                                                                                                                                                                      [HEAD]
    [initial commit]                                                                                                                                                                                  [master]
    o-------------------------------o-------------------------------o-------------------------------o--------------------------------------------------------------------------------------------------o
    |                               |                               |\------------------------------|--------------------------------o--------------------------------o-------------------------------/|
    Add a Main thing                Add a Sub thing                 Add another Sub thing           Add another Main thing           Fix Sub somehow                  Fix Sub further                  Merge subhistory branch 'subproj' under path/to/sub/
     __________________________      __________________________      __________________________      __________________________       __________________________       __________________________       __________________________
    |                          |    |                          |    |                          |    |                          |     |                          |     |                          |     |                          |
    |  Files:                  |    |  Files:                  |    |  Files:                  |    |  Files:                  |     |  Files:                  |     |  Files:                  |     |  Files:                  |
    |  + a-Main-thing          |    |    a-Main-thing          |    |    a-Main-thing          |    |    a-Main-thing          |     |    a-Main-thing          |     |    a-Main-thing          |     |    a-Main-thing          |
    |                          |    |  + path/to/sub/          |    |    path/to/sub/          |    |  + another-Main-thing    |     |    path/to/sub/          |     |    path/to/sub/          |     |  < another-Main-thing    |
    |                          |    |  +   a-Sub-thing         |    |      a-Sub-thing         |    |    path/to/sub/          |     |      a-Sub-thing         |     |      a-Sub-thing         |     |    path/to/sub/          |
    |                          |    |                          |    |  +   another-Sub-thing   |    |      a-Sub-thing         |     |      another-Sub-thing   |     |      another-Sub-thing   |     |      a-Sub-thing         |
    |                          |    |                          |    |                          |    |      another-Sub-thing   |     |  +   fix-Sub-somehow     |     |      fix-Sub-somehow     |     |      another-Sub-thing   |
    |                          |    |                          |    |                          |    |                          |     |                          |     |  +   fix-Sub-further     |     |  >   fix-Sub-somehow     |
    |                          |    |                          |    |                          |    |                          |     | [Note: no                |     |                          |     |  >   fix-Sub-further     |
    |                          |    |                          |    |                          |    |                          |     |  another-Main-thing yet] |     |                          |     |                          |
    |__________________________|    |__________________________|    |__________________________|    |__________________________|     |__________________________|     |__________________________|     |__________________________|

See that? The commits on `subproj` that fixed Sub after adding
`another-Sub-thing` were effortlessly transmuted into commits that fix
Sub inside `path/to/sub/` after adding `path/to/sub/another-Sub-thing`,
allowing them to merge cleanly like they clearly should, no commits
duplicated.

### Description

- `git-subhistory split <subproj-path> [(-b | -B) <subproj-branch>]`

  Literally just uses the `--subdirectory-filter` of `git-filter-branch`,
  which does pretty much the same thing as `git-subtree split`: it
  generates a completely new, synthetic commit graph of the history of
  just "Sub's" directory. Like the commit history shown by
  `git log --graph "path/to/sub/"`, it includes only commits that
  affected `path/to/sub/`, but each commit is rewritten so its root tree
  is the `path/to/sub/` subtree.

- `git-subhistory assimilate <subproj-path> <subproj-branch>`

  Invert `split`: look through the commits on `<subproj-branch>` for
  synthetic commits that were generated by splitting out some ancestor
  of `HEAD`, and then on top of the original "Main" commits those
  synthetic commits were generated from, generates more synthetic
  commits that make the same change as the "Sub" commits but to
  `path/to/sub/` in "Main" instead.  
  (Note: synthetic merge commits are tricky, because the "Main" trees of
   their parents may conflict. `git-subhistory` tries to create the
   simplest synthetic merge commits, but currently prioritizes
   guaranteeing that `ASSIMILATE_HEAD` be a clean merge into `HEAD`. This
   may change: mayhaps in the future simplicity of synthetic merge
   commits is prioritized, and `git-subhistory` merge will be made more
   sophisticated and will automatically resolve conflicts in the "Main"
   tree outside `path/to/sub/` in favor of `HEAD`.)  
  (Note: it is recommended to only split from/merge into the same Main
   branch. TODO: explain why merging in commits split from another
   branch can be like cherry-picking.)

- `git-subhistory merge <subproj-path> <subproj-branch>`

  Almost literally just
  `git-subhistory assimilate "$@" && git merge ASSIMILATE_HEAD`.

#### Notes

- working directory:
  Unlike `git-submodule` and `git-subtree`, `git-subhistory` does NOT "need to
  [be run] from the toplevel of the working tree", run it wherever you
  damn well please, even inside `path/to/sub/` with `.` as `<subproj-path>`.

- `SPLIT_HEAD`:
  All commands run `git-subhistory split` at some point, mutating
  `SPLIT_HEAD` to be `HEAD` split at `<subproj-path>`.

- grafts/replacement refs:
  Synthetic commits are all created with `git-filter-branch`, which honors
  the `info/grafts` file and refs in `refs/replaces/`. Grafts and
  replacement refs will hence be permanently baked into the synthetic
  commit histories. Changing relevant ones will cause subsequent
  synthetic history to not match up at all.
  (Potential TODO: creating synthetic grafts and replacement refs for
   the synthetic history? But originals and synthetic grafts/replacement
   refs would have to be modified in sync.)

### Comparison with `git-subtree`

I actually think `git-subtree` was halfway there, it got splitting pretty
much right, but then did merging wrong and had to needlessly complicate
splitting to deal with the broken merging. If you went through the
example above with equivalent `git-subtree` commands, the history after
splitting would be identical right down to the hashes, but after
merging, you'd get:

    [initial commit]                                                                                                                 [initial commit]                                                                                                                    [master]
    o-------------------------------o-------------------------------o-------------------------------o--------------------------------|-----------------------------------------------------------------------------------------------------------------------------------o
    |                               |                               |                               |                                o--------------------------------o--------------------------------o--------------------------------o-------------------------------/|
    Add a Main thing                Add a Sub thing                 Add another Sub thing           Add another Main thing           Add a Sub thing                  Add another Sub thing            Fix Sub somehow                  Fix Sub further                  Merge commit 'd535a7c' under subtree path/to/sub/
     __________________________      __________________________      __________________________      __________________________       __________________________       __________________________       __________________________       __________________________       __________________________
    |                          |    |                          |    |                          |    |                          |     |                          |     |                          |     |                          |     |                          |     |                          |
    |  Files:                  |    |  Files:                  |    |  Files:                  |    |  Files:                  |     |  Files:                  |     |  Files:                  |     |  Files:                  |     |  Files:                  |     |  Files:                  |
    |  + a-Main-thing          |    |    a-Main-thing          |    |    a-Main-thing          |    |    a-Main-thing          |     |  + a-Sub-thing           |     |    a-Sub-thing           |     |    a-Sub-thing           |     |    a-Sub-thing           |     |    a-Main-thing          |
    |                          |    |  + path/to/sub/          |    |    path/to/sub/          |    |  + another-Main-thing    |     |                          |     |  + another-Sub-thing     |     |    another-Sub-thing     |     |    another-Sub-thing     |     |  < another-Main-thing    |
    |                          |    |  +   a-Sub-thing         |    |      a-Sub-thing         |    |    path/to/sub/          |     |                          |     |                          |     |  + fix-Sub-somehow       |     |    fix-Sub-somehow       |     |    path/to/sub/          |
    |                          |    |                          |    |  +   another-Sub-thing   |    |      a-Sub-thing         |     |                          |     |                          |     |                          |     |  + fix-Sub-further       |     |      a-Sub-thing         |
    |                          |    |                          |    |                          |    |      another-Sub-thing   |     |                          |     |                          |     |                          |     |                          |     |      another-Sub-thing   |
    |                          |    |                          |    |                          |    |                          |     |                          |     |                          |     |                          |     |                          |     |  >   fix-Sub-somehow     |
    |                          |    |                          |    |                          |    |                          |     |                          |     |                          |     |                          |     |                          |     |  >   fix-Sub-further     |
    |                          |    |                          |    |                          |    |                          |     |                          |     |                          |     |                          |     |                          |     |                          |
    |__________________________|    |__________________________|    |__________________________|    |__________________________|     |__________________________|     |__________________________|     |__________________________|     |__________________________|     |__________________________|

Note the duplicate `Add a Sub thing` and `Add another Sub thing` commits.

What happened was, there were the originals, which add
`path/to/sub/a-Sub-thing` and `path/to/sub/another-Sub-thing` to Main,
right? They were split into commits which add `a-Sub-thing` and
`another-Sub-thing` to Sub, just like you'd want.

But then, `git-subtree merge` did `git merge --strategy subtree`, which
is a fine and dandy merge strategy, but `git-merge` always creates a
merge commit whose parents are the commits passed to it, and in this
case one is a commit to Main and one is a commit to Sub: notice how in
the merge commit, the subproject files `a-Sub-thing` and
`another-Sub-thing` are at different paths in the two parent commits.

Hence duplicated commits: the changes are to different paths.

By contrast, `git-subhistory merge` first does `git-subhistory assimilate`
to generate synthetic commits to Main from the upstream bugfixes to Sub,
so both parents of the merge commit are commits to Main. Importantly,
the synthetic commits are generated on top of the original subproject
commits, so instead of being duplicated, those originals are the merge
base, like they should be!

(Asides:

- `merge -s subtree` is actually awesome if you only ever merge in
  upstream changes and never split out changes to push upstream: next
  `merge -s subtree`, the commit that was last merged in using
  `merge -s subtree` will be the merge base, and Sub's commit history
  shows up in Main's commit history. Our problem with it is that if you
  do split out any commits, they get duplicated and can't serve as a
  merge base and will never fast-forward.
- `git-subtree split` doesn't just serve the same purpose as
  `git-subhistory split`, it actually does almost exactly the same thing
  and often generates identical commits with identical hashes. In fact,
  I started out trying to fork `git-subtree`, intending to add an
  alternative way to merge, until I discovered that `git-subtree split`
  was not just `git filter-branch --subdirectory-filter`, it "manually"
  loops through history and calls `git commit-tree`. I don't know
  exactly why but I'm pretty sure that's because it does something
  special with `merge -s subtree` commits, which is where
  `git-subtree`-generated commits start diverging from plain old
  `git filter-branch --subdirectory-filter`-generated commits (which
  what `git-subhistory split` does).
- Because of all this, most `git-subtree` tutorials I've seen actually
  recommend using `--squash` when merging, which creates a synthetic
  commit combining all upstream changes to Sub since the last merge.
  This solves the duplicate commit problem, but no upstream Sub commits
  are in Main's history, Main commits are never a fast-forward of any
  upstream Sub commits, and there will never be a merge-base. On
  projects I've worked on where we wanted to both push to and pull from
  an upstream Sub repo, we decided that was worse than submodules and
  used submodules instead.

)
