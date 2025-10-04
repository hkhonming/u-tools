#!/bin/bash

usage() {
    echo "Usage: $0 <Ubuntu source tree> <git branch> <Ubuntu kernel version>"
    echo "  <Ubuntu source tree>: A git/http URL to fetch target derivative kernel"
    echo "  <git branch>: E.g. master-next" 
    echo "  <Ubuntu kernel version>: E.g. 5.15, 6.8"
    exit 1
}

# Check if exactly two arguments were provided
if [ "$#" -ne 3 ]; then
    echo "Error: This script requires exactly 3 arguments." >&2
    usage
fi

GIT_URL="$1"
BRANCH="$2"
VERSION="$3"

git clone -b $BRANCH --bare --filter=blob:none --single-branch $GIT_URL work_dir
cd work_dir
git log --grep "UBUNTU: Ubuntu-$VERSION" | head -n 7
SHA=`git log --grep "UBUNTU: Ubuntu-$VERSION" | head -n 1 | cut -f 2 -d " "`

echo "### Commits on top of generic Ubuntu ###"
git rev-list --count $SHA..$BRANCH
echo "### Differences on top of generic Ubuntu ###"
git diff --shortstat $SHA..$BRANCH


