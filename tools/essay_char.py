'''
改用八股文字频
'''

from collections import defaultdict
import math

weight_table = defaultdict(int)
with open('/Library/Input Methods/Squirrel.app/Contents/SharedSupport/essay.txt', 'r') as f:
    for l in f:
        l = l.strip()
        [k,v] = l.split('\t')
        v = int(v)
        weight_table[k]=v

# main2.txt is the output of luna_like.py
import sys
with open('main2.txt') as f:
    for l in f:
        l = l.strip('\n')
        print(l, file=sys.stderr)
        [zi, zrm, weight, comment] = l.split('\t')
        auto = False
        if 'auto' in comment:
            auto = True
        if weight == '':
            factor = 1
        elif weight == '0':
            factor = 0
        else:
            factor = float(weight[:-1]) / 100
        essay_w = weight_table.get(zi, 0.0)
        auto_str = "# auto" if auto else ""
        print(f'{zi}\t{zrm}\t{math.ceil(essay_w * factor)}\t{auto_str}')
