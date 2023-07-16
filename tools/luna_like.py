# 生成類似 luna pinyin 的單字表

import sys

from collections import defaultdict
from zrmify import zrmify1, zrmify
import radical

original_set = set()
fvm_table = defaultdict(list)
original_table = defaultdict(list)
with open('main.txt') as f:
    for line in f:
        [zi, code, *_] = line.strip().split()
        original_table[zi].append(code)
        original_set.add(zi)
        fvm = code.split(';')[1]
        if fvm not in fvm_table[zi]:
            fvm_table[zi].append(fvm)

# 根據規則自動拆字
def guess_fvm(ch):
    import radical
    from pypinyin import lazy_pinyin
    rad = radical.radical(ch)
    res = radical.residue(ch)
    if not rad or not res:
        print(f'⚠️{ch}, rad={rad}, res={res}')
        return None
    def code(x):
        if x=='扌': return 'f'
        elif x=='彳': return 'x'
        elif x in '日月曰目': return 'o'
        else: return zrmify1(lazy_pinyin(x)[0])[0]
    return code(rad) + code(res[0])

luna_set = set()
bad_lines = []
with open('luna_chars.txt') as f:
    for line in f:
        line = line.strip()
        [zi, pinyin, *maybe_weight] = line.strip().split('\t')

        # skip strange code
        if pinyin == 'lvan': continue

        for fvm in fvm_table[zi]:
            try:
                zrm = zrmify1(pinyin) + ';' + fvm
            except:
                print('⚠️ cannot encode %s %s' % (zi, pinyin))
                continue

            if len(maybe_weight) > 0:
                print(f'{zi}\t{zrm}\t{"".join(maybe_weight)}')
            else:
                print(f'{zi}\t{zrm}')
            luna_set.add(zi)

        # no fvm found, guess one
        fvm = None
        if len(fvm_table[zi]) == 0:
            fvm = guess_fvm(zi)
            if fvm:
                zrm = zrmify1(pinyin) + ';' + fvm
                print(f'{zi}\t{zrm}\t{"".join(maybe_weight)}  # auto')
            else:
                bad_lines.append(line)

print('#----------')
zrm_unique_set = original_set - luna_set
for c in zrm_unique_set:
    for code in original_table[c]:
        if code[:2] in ["pp", "jv", "qv", "yv"]: continue
        print(f'{c}\t{code}')
print('#----------')
for line in bad_lines: print(line)
