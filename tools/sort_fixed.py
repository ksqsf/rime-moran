# 之前把码表里的词顺序全弄乱了，现在重新整理
#
# 一个基本的想法是，对每个码里的词，按词频重排，词频来自于 essay 和 luna pinyin

from collections import defaultdict
import math

weight_table = defaultdict(int)
with open('/Library/Input Methods/Squirrel.app/Contents/SharedSupport/essay.txt', 'r') as f:
    for l in f:
        l = l.strip()
        [k,v] = l.split('\t')
        v = int(v)
        weight_table[k]=v

table = defaultdict(list)
extra_table = defaultdict(list)
with open('fixed.txt') as f:
    for l in f:
        l = l.strip()
        [code, txt, *rest] = l.split('\t')
        table[code].append(txt)
        extra_table[code].append(rest)

for code, txts in table.items():
    extras = extra_table[code]
    txts.sort(key=lambda x: -weight_table.get(x, 0))
    for txt, extra in zip(txts, extras):
        extra_str = "" if len(extra)==0 else "\t" + "".join(extra)
        print(f'{code}\t{txt}{extra_str}')
