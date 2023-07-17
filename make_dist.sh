#!/bin/bash

rm -rf dist
mkdir -p dist
cp -a README.md etc dist
cp -a lua opencc dist
cp -a moran*.yaml dist
cp -a default.custom.yaml squirrel.custom.yaml symbols.yaml dist
cp -a zh-hant-t-essay-*.gram dist
cp -a tiger*.yaml dist
cp -a njerchet*.yaml dist
cp -a 下载与安装说明.txt  dist

