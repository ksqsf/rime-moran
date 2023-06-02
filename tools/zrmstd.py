"""
查詢標準輔碼
"""

codes = dict()

with open('zrmstd.txt', 'r') as f:
    for l in f:
        try:
            [text, code] = l.strip().split('\t')[:2]
        except:
            continue
        code = code.split(';')[1]
        codes[text] = code


def zrmstd(char):
    return codes[char]
