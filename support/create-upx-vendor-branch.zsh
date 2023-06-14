#! /usr/bin/env zsh
## vim:set ft=zsh ts=4 sw=4 et:
set -e; set -o pipefail; unsetopt NULL_GLOB

export LC_ALL=C.UTF-8
export TZ=UTC0
d=$(git rev-parse --show-toplevel)
[[ -z $d || ! -d $d ]] && exit 1
cd $d || exit 1

function check_git_clean() {
    if ! git diff --quiet; then
        git status || true
        git diff || true
        echo "ERROR: git is not clean"
        exit 1
    fi
}

function create_warning() {
    local f=README.md
    [[ -e $f ]] && f=README-upx-vendor.md
    echo -e 'WARNING\n=======

The `upx-vendor` branch in this git submodule is created automatically
from the `devel` branch and will get forcefully overwritten.

DO NOT MAKE ANY CHANGES IN THIS BRANCH!' > $f
}

current_branch=$(git rev-parse --abbrev-ref HEAD)
check_git_clean
git checkout devel
devel_rev=$(git rev-parse --short=12 HEAD)
devel_date=$(git show -s '--format=%ct' HEAD)

# 1) copy devel files to $tmpdir
tmpdir=$(mktemp -d -t upx-vendor-XXXXXX)
[[ -d $tmpdir ]] || exit 1
mkdir -p $tmpdir/include/valgrind
cp -ai COPYING $tmpdir
cp -ai callgrind/callgrind.h dhat/dhat.h drd/drd.h helgrind/helgrind.h memcheck/memcheck.h $tmpdir/include/valgrind
sed 's/@VG_VER_MAJOR@/3/;s/@VG_VER_MINOR@/22/' < include/valgrind.h.in > $tmpdir/include/valgrind/valgrind.h
# 2) create new orphan tmp-branch
if git rev-parse -q --verify tmp-branch >/dev/null; then
    git branch -D tmp-branch
fi
git checkout --orphan tmp-branch
git rm -q -rf .
# 3) copy $tmpdir files back to tmp-branch
cp -ai $tmpdir/* .
# 4) remove unused files
# 5) cleanup files (whitespace)
find . -type d -name '.git' -prune -o -type f -print0 | xargs -0r sed -i -e 's/[ \t]*$//'
for f in include/*/*.h; do expand -t 8 $f > $f.tmp; mv $f.tmp $f; done
for f in include/*/*.h; do sed -i -e '/./,$!d' $f; done
for f in include/*/*.h; do sed -i -e ':a' -e '/^\n*$/{$d;N;ba' -e '}' $f; done
# 6) add files and commmit
create_warning
git add .
u='upx-vendor-bot[bot]'; m='none@none'; d="$devel_date +0000"
GIT_AUTHOR_NAME=$u GIT_COMMITTER_NAME=$u \
GIT_AUTHOR_EMAIL=$m GIT_COMMITTER_EMAIL=$m \
GIT_AUTHOR_DATE=$d GIT_COMMITTER_DATE=$d \
git commit -q -a -m "Automatically created from git devel branch $devel_rev"

check_git_clean
if ! git rev-parse -q --verify upx-vendor >/dev/null; then
    git branch -m tmp-branch upx-vendor
    echo "===== upx-vendor branch created."
elif ! git diff --quiet ..upx-vendor; then
    git branch -D upx-vendor
    git branch -m tmp-branch upx-vendor
    echo "===== upx-vendor branch NEW version."
else
    git checkout upx-vendor
    git branch -D tmp-branch
    echo "===== upx-vendor branch is up-to-date."
fi

rm -rf $tmpdir

check_git_clean
git checkout $current_branch

# check that license files in master branch are up-to-date
git diff --exit-code upstream..master COPYING
