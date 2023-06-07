"""
給八股文詞庫的所有二字詞註音

輸入文件格式：
text1\tweight1
text2\tweight2
...
"""

from pypinyin import lazy_pinyin
from zrmify import zrmify1
from zrmstd import zrmstd
import opencc
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



conv = opencc.OpenCC()


def code_all(text):
    pys = lazy_pinyin(conv.convert(text))
    ups = [zrmify1(py) for py in pys]
    iterables = []
    for (up, char) in zip(ups, text):
        codes = []
        for f in 辅码表[char]:
            codes.append(up + ';' + f)
        iterables.append(iter(codes))
    return [' '.join(code) for code in itertools.product(*iterables)]


def code_std(text):
    pys = lazy_pinyin(conv.convert(text))
    return ' '.join(up + ';' + zrmstd(c) for (up, c) in zip(ups, text))


def main():
    with open('input.txt', 'r') as f:
        for l in f:
            [text, _code, weight] = l.strip().split('\t')
            weight = float(weight)
            if len(text) > 1:
                try:
                    all_codes = code_all(text)
                    if len(all_codes) > 5:
                        print(f'{text}\t{code_std(text)}\t{weight:g}')
                    for code in code_all(text):
                        print(f'{text}\t{code}\t{weight:g}')
                except:
                    print(f'{text}\t\t{weight:g}')
            else:
                print(f'{text}\t\t{weight:g}')


if __name__ == '__main__':
    main()
