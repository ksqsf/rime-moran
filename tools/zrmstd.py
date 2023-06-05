"""
查詢標準輔碼和讀音
"""

from collections import defaultdict


codes = dict()
udpns = defaultdict(list)
bad = []

with open('zrmstd.txt', 'r') as f:
    for l in f:
        [text, code] = l.strip().split('=')
        if code not in codes:
            codes[text] = code


with open('zrmup.txt', 'r') as f:
    for l in f:
        [text, code] = l.strip().split()
        if code not in udpns[text]:
            udpns[text].append(code)


def zrmstd(char):
    return codes[char]


def zrmups(char):
    return udpns[char]
