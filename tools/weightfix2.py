# 修復 main dict 中不常用讀音詞頻太高的問題

import opencc
from pypinyin import lazy_pinyin
from zrmify import *



entries = []


with open('../moran.main.dict.yaml', 'r') as f:
    flag = False
    for l in f:
        l = l.strip()
        if not flag and l == '#----------':
            flag = True
            continue
        if flag and l == '#----------':
            break
        if not flag:
            continue
        [char, code, w] = l.split()
        entries.append((char, code, w))


def is_common_reading_of(char, up):
    py = lazy_pinyin(char)[0]
    if py == char:
        return True
    else:
        try:
            return zrmify1(py) == up
        except:
            print(f'ERR: {char} 沒有正確的讀音數據，其拼音是 {py}, 雙拼是 {up}')
            return True


with open('output.txt', 'w') as f:
    for (char, code, w) in entries:
        [up, _] = code.split(';')
        if is_common_reading_of(char, up):
            f.write(f'{char}\t{code}\t{w}\n')
        else:
            f.write(f'{char}\t{code}\t{int(w)//20}\n')
