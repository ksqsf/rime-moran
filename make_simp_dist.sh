#!/bin/bash

set -e
set -x

PYTHON=${PYTHON:-python3}

# 若 BUILD_TYPE 为 github，则在准备完内容后直接退出，由 GitHub 负责 zip 打包。
# 否则调用 7z 产生 7z 包。
BUILD_TYPE="$1"

########################################################################
# 从 git HEAD 中产生 dist 目录
########################################################################
rm -rf dist/
git archive HEAD -o archive.tar
mkdir -p dist
tar xf archive.tar -C dist
rm archive.tar
cd dist


########################################################################
# 更新单字字频
# 这一步把 moran.chars.dict.yaml 中的字频替换成 data/pinyin_simp.txt 中
# 的频率信息，使得简体字排在繁体字之前。
########################################################################
echo 更新单字字频...
cd tools
$PYTHON schemagen.py --pinyin-table=./data/pinyin_simp.txt  update-char-weight --rime-dict=../moran.chars.dict.yaml > ../moran.chars.dict.yaml.bak
mv ../moran.chars.dict.yaml{.bak,}
cd ..


########################################################################
# 替换辅助码
# 这一步把词库（compact_dicts）中的辅助码替换成简体字形的辅助码。
########################################################################
echo 替换辅助码...
compact_dicts=(
    "moran.base.dict.yaml"
    "moran.tencent.dict.yaml"
    "moran.moe.dict.yaml"
    "moran.computer.dict.yaml"
    "moran.hanyu.dict.yaml"
    "moran.words.dict.yaml"
)

simplifyDict() {  # 将 $1 中的所有汉字繁转简
    cp $1 $1.bak
    opencc -c opencc/moran_t2s.json -i $1.bak -o $1
    rm $1.bak
}

for dict in "${compact_dicts[@]}"; do
    simplifyDict $dict
done

(cd tools/ && ./update_compact_dicts.sh)

darwin=false;
case "`uname`" in
  Darwin*) darwin=true ;;
esac

sedi () {
    case $(uname -s) in
        *[Dd]arwin* | *BSD* ) sed -i '' "$@";;
        *) sed -i "$@";;
    esac
}


########################################################################
# 替換碼表
# 简体版中首选使用 moran_fixed_simp 码表
########################################################################
echo 替換碼表...
sedi 's/dictionary: moran_fixed/dictionary: moran_fixed_simp/' moran_fixed.schema.yaml
sedi 's/dictionary: moran_fixed/dictionary: moran_fixed_simp/' moran_aux.schema.yaml 
sedi 's/dictionary: moran_fixed/dictionary: moran_fixed_simp/' moran.schema.yaml 


########################################################################
# 替换简体语法模型
# 简体版中首选使用简体八股文模型
########################################################################
echo 替换简体语法模型...
wget 'https://github.com/lotem/rime-octagram-data/raw/hans/zh-hans-t-essay-bgc.gram' -O zh-hans-t-essay-bgc.gram
wget 'https://github.com/lotem/rime-octagram-data/raw/hans/zh-hans-t-essay-bgw.gram' -O zh-hans-t-essay-bgw.gram
rm zh-hant-t-essay-bg{c,w}.gram
sedi 's/zh-hant-t-essay-bgw/zh-hans-t-essay-bgw/' moran.yaml
sedi 's/zh-hant-t-essay-bgc/zh-hans-t-essay-bgc/' moran.yaml


########################################################################
# 替换 simplification 为 traditionalization
# 繁体版中 opencc 转换用于繁转简，简体版中改为简转繁
########################################################################
for f in *.schema.yaml moran.yaml ; do
    sedi 's/simplification/traditionalization/' $f
    sedi 's/漢字, 汉字/汉字, 漢字/' $f
    sedi 's/moran_t2s.json/s2t.json/' $f
done


########################################################################
# 替换 emoji 用字为简体字
########################################################################
simplifyDict opencc/moran_emoji.txt
sort -k 1,1 -u opencc/moran_emoji.txt > /tmp/moran_emoji.txt
mv /tmp/moran_emoji.txt opencc/moran_emoji.txt


########################################################################
# 部分 lua 中输出繁体字，也做转换
########################################################################
simplifyDict lua/moran_shijian.lua
simplifyDict lua/moran_charset_comment_filter.lua
simplifyDict lua/moran_pin.lua
simplifyDict moran_custom_phrases.txt

########################################################################
# 打包
########################################################################
cd ..
echo 打包...

if [ x$BUILD_TYPE = x"github" ]; then
    # GitHub Actions will take over the tarball creation.
    rm -rf dist/tools dist/.git dist/.github dist/make_simp_dist.sh
    exit 0
fi

rm -rf dist/tools
rm -rf dist/.git dist/.github dist/.gitignore
rm -rf dist/make_simp_dist.sh
cp 下载与安装说明.txt 更新纪要.txt dist
sedi 's/MORAN_VARIANT/简体/' dist/下载与安装说明.txt

7z a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on "MoranSimplified-$(date +%Y%m%d).7z" dist
rm -rf dist
