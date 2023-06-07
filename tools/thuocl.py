"""生成合法的 thuocl 词库

需要先把 thuocl-pinyin 项目 [1] output 目录中的所有 .csv 文件拷贝到当前目录下

[1] https://github.com/ksqsf/THUOCL-pinyin
"""

from zrmify import *
import os
import sys
import pandas as pd
import glob
from zrmstd import *
from collections import defaultdict
import itertools


双拼表 = defaultdict(set)  # 双拼
辅码表 = defaultdict(set)  # 辅码

started = False
for line in open('../moran.main.dict.yaml'):
    line = line.strip()
    if not started:
        if line == '#----------':
            started = True
        else:
            continue
    else:
        if line == '#----------':
            break
        [字, 码, *_] = line.split()
        [双拼, 辅码] = 码.split(';')
        双拼表[字].add(双拼)
        辅码表[字].add(辅码)


def code_udpn(词, 双拼):
    """双拼是列表 如 ['ni', 'hk']"""
    if len(词) == 0:
        return []
    elif len(词) == 1:
        字 = 词[0]
        # 做一个简单的筛选，去除没用的容错码
        # 1. 如果一个字的第一个辅码既有 f 又有 t，则只选 f —— 提手旁
        # 2. 如果一个字的第一个辅码既有 o 又有 y，则只选 o —— 月
        # 这个规则必然有一些错误，但是既然是打词，就没必要太关注辅码了
        提手旁 = False
        月 = False
        日 = False
        initials = {辅码[0] for 辅码 in 辅码表[字]}
        if 'f' in initials and 't' in initials: 提手旁 = True
        if 'r' in initials and 'o' in initials: 月 = True
        if 'y' in initials and 'o' in initials: 日 = True
        for 辅码 in 辅码表[字]:
            if 提手旁 and 辅码[0] == 't': continue
            if 日 and 辅码[0] == 'r': continue
            if 月 and 辅码[0] == 'y': continue
            yield [双拼[0] + ';' + 辅码]
    else:
        字 = 词[0]
        for 辅码 in 辅码表[字]:
            for 后续 in code_udpn(词[1:], 双拼[1:]):
                yield [双拼[0] + ';' + 辅码] + 后续


def code_std(词,拼音):
    """拼音是个空格分隔的字符串 如 'ni hao' """
    ups = zrmify(拼音).split()
    return ' '.join(up + ';' + zrmstd(c) for (up, c) in zip(ups, 词))


def code_all(词, 拼音):
    """拼音是个空格分隔的字符串 如 'ni hao' """
    ups = zrmify(拼音).split()

    iterables = []
    for (up, char) in zip(ups, 词):
        codes = []
        for f in 辅码表[char]:
            codes.append(up + ';' + f)
        iterables.append(iter(codes))

    return [' '.join(code) for code in itertools.product(*iterables)]

for csv in glob.glob('*.csv'):
    if csv == 'freq.csv': continue
    df = pd.read_csv(csv)
    dict_name = csv[:-4]
    dict_name = f'moran.thuocl.{dict_name}'
    print('processing dict', dict_name)
    with open(f'../{dict_name}.dict.yaml', 'w', encoding='utf-8-sig') as f:
        f.write('''# Rime dictionary
# encoding: utf-8

---
name: {dict_name}
version: "0.1"
sort: by_weight
use_preset_vocabulary: false
...

'''.format(dict_name=dict_name))
        for index, row in df.iterrows():
            word = row['trad_word']
            pinyin = row['pinyin'].strip()
            freq = row['freq']
            if freq < 50: continue
            try:
                codes = code_all(word, pinyin)
                if len(codes) > 5:
                    codes = [code_std(word, pinyin)]
                for code in codes:
                    print(f'{word}\t{code}\t{freq}', file=f)
            except Exception as e:
                print('! 无法编码词语:', word, str(e))
                import traceback
                # traceback.print_exc()
