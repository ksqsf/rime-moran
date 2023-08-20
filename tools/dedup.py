# Author: ksqsf
# Released into the Public Domain

"""
列出所有我不用的容错码
"""

from zrmify import *
import os
import sys
import pandas as pd
import glob


双拼表 = {}  # 双拼
辅码表 = {}  # 辅码

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
        if 字 not in 双拼表: 双拼表[字] = set()
        if 字 not in 辅码表: 辅码表[字] = set()
        双拼表[字].add(双拼)
        辅码表[字].add(辅码)


所有规则 = [
    ('手', ['f', 't']),  # 优先选择第一个码
    #('日', ['o', 'r']),
    #('目', ['o', 'm']),
    #('月', ['o', 'y']),
]


输出 = {}

for 规则名, _ in 所有规则:
    输出[规则名] = set()


所有字 = list(双拼表.keys())
for 字 in 所有字:
    所有首辅码 = {辅码[0] for 辅码 in 辅码表[字]}
    for (规则名, 所有容错码) in 所有规则:
        if all(首辅码 in 所有首辅码 for 首辅码 in 所有容错码):
            输出[规则名].add(字)



for 规则名, _ in 所有规则:
    print(f'{规则名}: {"".join(输出[规则名])}')





started = False
output = open('output.txt', 'w')
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
        [字, 码, *其他] = line.split()
        [双拼, 辅码] = 码.split(';')
        ok = True
        for rulename, codes in 所有规则:
            if 字 in 输出[rulename]:
                if 辅码[0] != codes[0]:
                    ok = False
                    break
        if ok:
            print('{}\t{};{}\t{}'.format(字,双拼,辅码,"\t".join(其他)), file=output)
