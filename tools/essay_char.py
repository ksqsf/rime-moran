'''
改用八股文字频
'''

from collections import defaultdict
import math

table = defaultdict(int)
with open('/Library/Input Methods/Squirrel.app/Contents/SharedSupport/essay.txt', 'r') as f:
    for l in f:
        l = l.strip()
        [k,v] = l.split('\t')
        v = int(v)
        table[k]=v

with open('main.txt') as f:
    for l in f:
        l = l.strip()
        [zi, zrm, *maybe_weight] = l.split('\t')
        auto = False
        if len(maybe_weight) == 0:
            factor = 0
        elif len(maybe_weight) == 1:
            wstr = maybe_weight[0]
            if 'aut' in wstr:
                factor = 0
                auto = True
            elif wstr == '0':
                factor = 0
            else:
                factor = float(wstr[:-1]) / 100
        else:
            print(f'⚠️ {zi} {maybe_weight}')
        essay_w = table.get(zi, 0.0)
        auto_str = "# auto" if auto else ""
        print(f'{zi}\t{zrm}\t{math.ceil(essay_w * factor)}\t{auto_str}')
