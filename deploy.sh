#!/bin/bash
mkdir -p .deploy/.git
cp -r .git .deploy/
cd .deploy
git checkout gh-pages
rm -rf `ls`
cd ../
hexo clean && hexo generate
cp -r ./public/* .deploy/
cd .deploy
git add .
git commit -m 'deploy'
git push
cd ../
rm -rf .deploy


# pwd=$(basename "$PWD")
# tempdir="../.temp"
# cpdir=$tempdir"/"$pwd"/"
# rm -rf $tempdir
# mkdir -p $cpdir
# cp -r ./ $cpdir
# cd $cpdir
# hexo clean && hexo generate
# cp -r ./public ../
# git checkout gh-pages
# rm -rf `ls`
# cp -r ../public/* ./
# git add . && git commit -m 'deploy' && git push
# cd ../../$pwd
# rm -rf $tempdir