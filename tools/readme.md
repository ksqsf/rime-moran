以前的腳本參見 [commit ffdd6b28](https://github.com/ksqsf/rime-moran/tree/ffdd6b280a3ee90745221a328e8e54bc62f2ee6a/tools)。

# 簡化字方案生成

```
# 單字碼表
python3 schemagen.py --pinyin-table data/pinyin_simp.txt gen-chars | grep -v '??'

# 詞語碼表
python3 schemagen.py --pinyin-table data/pinyin_simp.txt gen-dict --input-dict data/simp_words.txt

# 簡碼碼表
python3 schemagen.py --pinyin-table data/pinyin_simp.txt gen-fixed --format code-word  --charset data/simp_chars.txt  --input-dict data/simp_words.txt 
```
