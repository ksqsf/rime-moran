# 基于 essay 检查 fixed 码表中是否有三码分配不合理的现象

from itertools import product
from collections import defaultdict
from essaydb import *
from operator import itemgetter, attrgetter

alphabet = 'abcdefghijklmnopqrstuvwxyz'
product(iter(alphabet), iter(alphabet), iter(alphabet))
segments = defaultdict(list)
table = defaultdict(list)
rtable = defaultdict(list)

with open('fixed.txt') as f:
    for l in f:
        l = l.strip()
        [code, text, *_] = l.split('\t')
        table[code].append(text)
        rtable[text].append(code)
        if len(code) >= 3 and len(text) == 1:
            segments[code[:3]].append((code, text, essay_weight(text)))

for code, segment in segments.items():
    segment.sort(key=itemgetter(2))
    char = segment[-1][1]
    if len(table[code]) > 0 and table[code][0] != char:
        print(f'Mismatch: {code} -> {table[code]}, but char={char} is better')
