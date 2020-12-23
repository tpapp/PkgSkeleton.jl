#!/bin/sh
# Create a test repository in a directy with files at various states. Each contains the filename.
# The corresponding template has the same files, to check which are overwritten.
echo "creating test repo in $1"
mkdir -p $1
cd $1
git init
echo "comitted" > comitted
echo "staged" > staged
echo "untracked" > untracked
git add comitted
touch "in_repo_unstaged"
git add in_repo_unstaged
git commit -m "commit1"
echo "git test repo in $TMP_DIR"
git add staged
echo "in_repo_unstaged" > in_repo_unstaged
