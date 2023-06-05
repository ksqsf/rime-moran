from zrmify import *
from zrmstd import *
from pypinyin import lazy_pinyin


def load_txt(path):
    res = []
    with open(path, 'r') as f:
        for l in f :
            if l.startswith('#'):
                continue
            res.append(l.strip())
    return res


def normalize_word(word):
    return word.replace('，', '').replace('。', '')


def encode_word(word):
    assert len(word) > 1
    word = normalize_word(word)
    pys = lazy_pinyin(word)
    ups = [zrmify1(py) for py in pys]
    if len(word) == 2:
        return ups[0] + ups[1]
    elif len(word) == 3:
        return ups[0][0] + ups[1][0] + ups[2]
    else:
        return ups[0][0] + ups[1][0] + ups[2][0] + ups[-1][0]


def encode_char(char):
    assert len(char) == 1
    return [ up + zrmstd(char) for up in zrmups(char) ]


def encode(txt):
    if len(txt) == 1:
        return encode_char(txt)
    else:
        return encode_word(txt)

###
### 結果已寫入 moran_fixed.words
###
f = open('../moran_fixed.words.dict.yaml', 'w')
f.write('''# Rime dictionary
# encoding: utf-8

---
name: moran_fixed.words
version: "1"
sort: original
use_preset_vocabulary: false
...

''')
dic = load_txt('data/simp_words.txt')
for txt in dic:
    try:
        code = encode(txt)
        f.write(f'{txt}\t{encode(txt)}\n')
    except:
        import traceback
        print('#處理錯誤: ' + txt)
print('done')
