import regex
import os
import pypinyin
from zrmify import zrmify

def encode_word(word):
    pys = pypinyin.lazy_pinyin(word)
    ups = [ zrmify(py) for py in pys ]
    if len(word) == 3:
        return ups[0] + ups[1][0] + ups[2][0]
    else:
        raise RuntimeError(f'bad word {word}')

with open("../moran_fixed.dict.yaml", "r") as f:
    for line in f:
        line = line.rstrip()
        matches = regex.findall(r"^([a-z]+)	(\p{Han}{3})$", line)
        if len(matches) == 0:
            print(line)
            pass
        else:
            oldcode = matches[0][0]
            word = matches[0][1]
            # 保留3碼
            if len(oldcode) == 3:
                print(f'{oldcode}\t{word}')
            # 輸出全碼
            try:
                code = encode_word(word)
                print(f'{code}\t{word}')
            except:
                print('# bad word', word)
