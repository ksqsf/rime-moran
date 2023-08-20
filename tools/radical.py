# radical.py -- 部首和部首餘部信息
#
# Copyright (c) 2023  ksqsf
# License: LGPLv3

from cnradical import Radical, RunOption
radicalize = Radical(RunOption.Radical).trans_ch

fix = {}
with open('data/radical.txt') as f:
    for line in f:
        [zi, rad] = line.split()
        fix[zi] = rad.strip()

def radical0(c):
    if c in fix:
        return fix[c]
    else:
        return radicalize(c)

def radical(c):
    r = radical0(c)
    normal = {
        '黄': '黃',
        '户': '戶',
        '飠': '食',
        '亻': '人',
    }
    if r in normal: return normal[r]
    else: return r


error_radical_chars = []
error_residue_chars = []
result_radicals = {}
result_residues = {}

with open('data/chaizi.txt') as f:
    for line in f:
        line = line.strip()
        [zi, *chais] = line.split('\t')
        zi = zi.strip()
        if len(chais) == 0:
            #print('💥️ 字 %s 沒有拆分數據' % zi)
            continue

        # Get the radical
        rad = radical(zi)
        if rad is None:
            #print('💥️ 字 %s 沒有部首數據' % zi)
            error_radical_chars.append(zi)
            continue
        else:
            result_radicals[zi] = rad

        # The residue of a radical is empty.
        if zi == rad:
            result_residues[zi] = []
            continue

        # Find the true residue
        n_valid = 0
        valid_residues = []
        longest_known = 100000
        for chai in reversed(chais):
            chai = chai.replace('亻', '人')
            chai = chai.split(' ')
            try: chai.remove(rad)
            except ValueError: continue
            if len(chai) < longest_known:
                longest_known = len(chai)
                valid_residues = [chai]
                n_valid = 1
                result_residues[zi] = chai
            elif len(chai) == longest_known:
                n_valid += 1

        # Store the result
        if n_valid == 0:
            error_residue_chars.append(zi)
            #print('❌️ 未得 %s 之部餘, 拆分=%s' % (zi, str(chais)))
        elif n_valid > 1:
            #print('⚠️ %s 有多個可用的部部餘 %s' % (zi, str(valid_residues)))
            pass

def residue(c):
    return result_residues.get(c, None)
