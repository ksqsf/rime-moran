"""
查詢標準輔碼
"""

codes = dict()

with open('zrmstd.txt', 'r') as f:
    for l in f:
        [text, code] = l.strip().split('=')
        codes[text] = code


def zrmstd(char):
    return codes[char]
