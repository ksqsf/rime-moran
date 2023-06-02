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


def get_code(text):
    pys = lazy_pinyin(text)
    zrms = [zrmify1(py) for py in pys]
    stds = [zrmstd(c) for c in text]
    res = []
    for (zrm, std) in zip(zrms, stds):
        res.append(zrm + ';' + std)
    return ' '.join(res)


if __name__ == '__main__':
    with open('input.txt', 'r') as f:
        for l in f:
            [text, weight] = l.strip().split('\t')
            weight = float(weight)
            if len(text) > 1:
                try:
                    code = get_code(text)
                    print(f'{text}\t{code}\t{weight:g}')
                except:
                    print(f'{text}\t\t{weight:g}')
            else:
                print(f'{text}\t\t{weight:g}')
