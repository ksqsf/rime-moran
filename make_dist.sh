#!/bin/bash

rm -rf dist
mkdir -p dist
cp -a README.md  dist
cp -a etc lua opencc rime.lua dist
cp -a moran*.yaml dist
cp -a default.custom.yaml grammar.yaml squirrel.custom.yaml symbols.yaml dist
cp -a zh-hant-t-essay-*.gram dist
cp -a tiger*.yaml dist
cp -a njerchet*.yaml dist
