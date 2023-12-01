#!/bin/bash

BUILD_TYPE="$1"

rm -rf dist/
git archive HEAD -o archive.tar
mkdir -p dist
tar xf archive.tar -C dist
rm archive.tar
cd dist

# 更新单字字频
echo 更新单字字频...
cd tools
python3 schemagen.py --pinyin-table=./data/pinyin_simp.txt  update-char-weight --rime-dict=../moran.chars.dict.yaml > ../moran.chars.dict.yaml.bak
mv ../moran.chars.dict.yaml{.bak,}
cd ..


# 替换辅助码
echo 替换辅助码...
compact_dicts=(
    "moran.essay.dict.yaml"
    "moran.tencent.dict.yaml"
    "moran.moe.dict.yaml"
    "moran.thuocl.dict.yaml"
    "moran.computer.dict.yaml"
    "moran.hanyu.dict.yaml"
    "moran.words.dict.yaml"
)

simplifyDict() {
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

# 替換碼表
echo 替換碼表...
sedi 's|\&dict moran_fixed|\&dict moran_fixed_simp|' moran_fixed.defaults.yaml
sedi 's|fixed/dictionary: moran_fixed|fixed/dictionary: moran_fixed_simp|' moran.defaults.yaml

# 替换简体语法模型
echo 替换简体语法模型...
wget 'https://github.com/lotem/rime-octagram-data/raw/hans/zh-hans-t-essay-bgc.gram' -O zh-hans-t-essay-bgc.gram
wget 'https://github.com/lotem/rime-octagram-data/raw/hans/zh-hans-t-essay-bgw.gram' -O zh-hans-t-essay-bgw.gram
rm zh-hant-t-essay-bg{c,w}.gram
for f in *.defaults.yaml 
do
    sedi 's/zh-hant-t-essay-bgw/zh-hans-t-essay-bgw/' $f
    sedi 's/zh-hant-t-essay-bgc/zh-hans-t-essay-bgc/' $f
done

cd ..

# 打包

echo 打包...

if [ x$BUILD_TYPE = x"github" ]; then
    # GitHub Actions will take over the tarball creation.
    rm -rf dist/tools dist/.git dist/.github dist/make_simp_dist.sh
    exit 0
fi

rm -rf dist/tools
rm -rf dist/.git
cp 下载与安装说明.txt 更新纪要.txt dist
sedi 's/MORAN_VARIANT/简体/' dist/下载与安装说明.txt

if [ -x "$(command -v 7zz)" ]; then
    ZIP7=7zz
else
    ZIP7=7z
fi

$ZIP7 a -tzip -mx=9 -r "MoranSimplified-$(date +%Y%m%d).7z" dist
rm -rf dist
