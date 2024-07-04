#!/usr/bin/env python3

# schemagen.py -- 雙拼+輔助碼 Rime 方案生成工具
#
# Copyright (c) 2023-2024 ksqsf
#
# License: GPLv3, with the exception that the copyright of any
# generated output belongs to the user. (所生成碼表本身的著作權歸本程
# 序的使用者所有.)
#

import sys
import argparse
import traceback
from collections import *
from itertools import *
import zrmify
import flypyify
import math
import opencc
from pypinyin import lazy_pinyin
from operator import *
import re
import regex


double_pinyin_choices = ['zrm', 'flypy']
auxiliary_code_choices = ['zrm', 'user']

args = None
auxiliary_table = defaultdict(list)
pinyin_table = defaultdict(lambda: defaultdict(int))
charset = []

##################
### 單字處理例程 ###
##################
def dedup(list):
    seen = {}
    return [seen.setdefault(x, x) for x in list if x not in seen]


def read_txt_table(path):
    result = defaultdict(list)
    with open(path, 'r') as f:
        for line in f:
            [char, data, *_] = line.strip().split()
            result[char] += data.split()
            result[char] = dedup(result[char])
    return result


def to_double_pinyin(pinyin, schema=None):
    global args
    match schema or args.double_pinyin:
        case 'zrm':
            return zrmify.zrmify(pinyin)
        case 'flypy':
            return flypyify.flypyify(pinyin)
    raise ValueError('Unknown double pinyin ' + args.double_pinyin)


def from_double_pinyin(pinyin, schema=None):
    global args
    match schema or args.double_pinyin:
        case 'zrm':
            return zrmify.unzrmify(pinyin)
        case 'flypy':
            return flypyify.unflypyify(pinyin)
    raise ValueError('Unknown double pinyin ' + args.double_pinyin)


def convert_sp1(sp, to_):
    '''轉換一個雙拼碼 @sp 到 to_ 方案

    如：默認雙拼爲自然碼，sp="xc", to="flypy" 時輸出 "xn"'''
    global args
    py = from_double_pinyin(sp, args.double_pinyin)
    sp = to_double_pinyin(py, to_)
    return sp


def to_auxiliary_codes(char):
    global auxiliary_table
    if not auxiliary_table:
        match args.auxiliary_code:
            case 'zrm':
                auxiliary_table = read_txt_table('data/zrmdb.txt')
            case 'user':
                auxiliary_table = read_txt_table('data/userdb.txt')
            case _:
                raise ValueError('Unknown auxiliary code ' + args.auxiliary_code)
    return auxiliary_table[char]


def initialize_pinyin_table(skip_no_pinyin=False):
    global pinyin_table
    with open(args.pinyin_table, 'r') as f:
        for line in f:
            [word, pinyin, freq] = line.strip().split('\t')
            if not pinyin and skip_no_pinyin:
                continue
            elif not pinyin:
                pinyin = word_to_pinyin(word)
            pinyin_table[word][pinyin] = int(freq)



def pinyin_weight(word, py=None):
    global pinyin_table
    if len(pinyin_table) == 0:
        initialize_pinyin_table()
    if not py:
        py = word_to_pinyin(word)
    return pinyin_table[word][py]


def iter_char_codes(char, pinyin):
    try:
        double_pinyin = to_double_pinyin(pinyin)
        auxiliary_codes = to_auxiliary_codes(char) or [args.auxiliary_code_fallback]
        yield from (double_pinyin + ';' + ac for ac in auxiliary_codes)
    except:
        yield from iter([])


def char_codes(char, pinyin):
    if 'compact' in args and args.compact:
        try:
            return [next(iter_char_codes(char, pinyin))]
        except StopIteration:
            return []
    else:
        return list(iter_char_codes(char, pinyin))


def handle_gen_chars():
    initialize_pinyin_table()
    for (char, weight_table) in pinyin_table.items():
        if len(char) > 1:
            continue
        for (pinyin, weight) in weight_table.items():
            try:
                for code in iter_char_codes(char, pinyin):
                    print(f'{char}\t{code}\t{weight}')
            except Exception as e:
                print(f'# {char} {pinyin} {str(e)}')


##################
### 詞庫處理例程 ###
##################
opencc_for_pinyin = None
def word_to_pinyin(word):
    global opencc_for_pinyin
    if args and 'opencc_for_pinyin' in args:
        if not opencc_for_pinyin:
            opencc_for_pinyin = opencc.OpenCC(args.opencc_for_pinyin)
        maybe_pinyin = ' '.join(lazy_pinyin(opencc_for_pinyin.convert(word)))
        if all(c in " abcdefghijklmnopqrstuvwxyz" for c in maybe_pinyin):
            return maybe_pinyin
        else:
            # 有時 opencc 會輸出奇怪的字，導致拼音轉換失敗；這時候不再嘗試轉換
            return ' '.join(lazy_pinyin(word))
    else:
        return ' '.join(lazy_pinyin(word))


def iter_word_codes(word, pinyin=None):
    # filter out special symbols
    word = ''.join(regex.findall(r'\p{Han}', word))
    if not pinyin:
        pinyin = word_to_pinyin(word)
    yield from (' '.join(tuple) for tuple in product(*[char_codes(c, p) for (c, p) in zip(word, pinyin.split())]))


def word_codes(word, pinyin=None):
    return list(iter_word_codes(word, pinyin))


def read_input_dict():
    table = list()
    with open(args.input_dict, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('#'):
                continue
            try:
                [word, pinyin, *weight] = line.split('\t')
                if len(weight) == 0:
                    weight = 0
                else:
                    weight = int(weight[0])
            except:
                [word] = line.split('\t')
                pinyin = None
                weight = 0
            # support format <word> \t <weight> where there is no pinyin
            if pinyin and pinyin[0] in '0123456789':
                weight = int(pinyin)
                pinyin = None
            table.append((word, pinyin, weight))
    return table


opencc_for_output = None
def handle_gen_dict():
    global opencc_for_output
    for (word, pinyin, weight) in read_input_dict():
        output_word = word
        if args.opencc_for_output:
            if not opencc_for_output:
                opencc_for_output = opencc.OpenCC(args.opencc_for_output)
            output_word = opencc_for_output.convert(word)

        for code in iter_word_codes(output_word, pinyin):
            if 'no_freq' in args and args.no_freq:
                print(f'{output_word}\t{code}')
            else:
                # 輔助碼與 output_word 一致, 詞頻由 word 決定
                if not weight:
                    weight = pinyin_weight(word, pinyin)
                    weight = int(weight * float(args.freq_scale))
                print(f'{output_word}\t{code}\t{weight}')



###############
### 簡碼生成 ###
###############
def initialize_charset():
    global charset
    with open(args.charset, 'r') as f:
        for line in f:
            if len(line) == 0 or line.startswith('#'):
                continue
            charset.append(line[0])


def encode_fixed_word(word, pinyin=None, short=False):
    assert len(word) > 1
    if '，' in word:
        word = word.replace('，', '')
    if not pinyin:
        pinyin = word_to_pinyin(word)
    double_pinyin = to_double_pinyin(pinyin).split()
    # if len(word) == 2:
    #     A = double_pinyin[0][0]
    #     B = double_pinyin[1][0]
    #     a = to_auxiliary_codes(word[0])[0][0]
    #     b = to_auxiliary_codes(word[1])[0][0]
    #     return A+B+b+a
    if len(word) == 2:
        if not short:
            return ''.join(double_pinyin)
        else:
            return double_pinyin[0][0] + double_pinyin[1][0]
    elif len(word) == 3:
        if short:
            return double_pinyin[0][0] + double_pinyin[1][0] + double_pinyin[2][0]
        elif args.aabc:
            return double_pinyin[0] + double_pinyin[1][0] + double_pinyin[2][0]
        else:
            return double_pinyin[0][0] + double_pinyin[1][0] + double_pinyin[2]
    else:
        return double_pinyin[0][0] + double_pinyin[1][0] + double_pinyin[2][0] + double_pinyin[-1][0]

def encode_fixed_word_sunshine_strategy(word, pinyin=None):
    assert len(word) > 1
    if not pinyin:
        pinyin = word_to_pinyin(word)
    double_pinyin = to_double_pinyin(pinyin).split()
    if len(word) == 2:
        return [double_pinyin[0] + double_pinyin[1][0] + to_auxiliary_codes(word[1])[0][0],
                #encode_fixed_word(word,pinyin)
                ]
    elif len(word) == 3:
        return [double_pinyin[0][0] + double_pinyin[1][0] + double_pinyin[2][0] + to_auxiliary_codes(word[2])[0][0]]
    else:
        return [encode_fixed_word(word, pinyin)]

def handle_gen_fixed():
    initialize_charset()
    initialize_pinyin_table()

    table = defaultdict(list)
    encoded = defaultdict(list)

    def put_into_dict_char(word, code, py, max_len=4):
        nonlocal table, encoded
        assert len(word) == 1
        # 這個字有多個編碼，但如果某個已有編碼是當前編碼的前綴，則不再添加該額外編碼
        for existing_code in encoded[word]:
            if code.startswith(existing_code):
                return
        # 逐級嘗試把當前編碼放入簡碼
        tolerance = dict(zip([1,2,3], (int(s) for s in args.tolerance.split(','))))
        for i in range(1, max_len):
            if len(table[code[:i]]) < tolerance[i]:
                table[code[:i]].append(word)
                encoded[word].append(code[:i])
                return
        # 一簡到三簡已經全部用完
        table[code].append(word)

    def put_into_dict_word(word, code, pinyin, max_len=4):
        nonlocal table
        assert len(word) > 1

        # 不使用簡詞時，詞總是四碼
        if not args.short_word:
            table[code].append(word)
            return

        # 使用簡詞時，詞語嘗試多種編碼方式
        # - 一簡
        # - n字詞嘗試n簡
        # - 二字詞嘗試取前三碼
        # - fallback: 全碼
        short_codes = []   # all(c < 4 for c in short_codes)
        # 1. 一簡
        short_codes.append(code[0])
        # 2. 字數匹配的簡碼
        short_code = encode_fixed_word(word, pinyin, True)
        if len(short_code) < 4:
            short_codes.append(short_code)
        # 3. 前三碼
        if len(word) == 2:
            short_codes.append(code[:3])

        # 放入簡碼
        tolerance = dict(zip([1,2,3], (int(s) for s in args.tolerance.split(','))))
        for c in short_codes:
            if len(table[c]) < tolerance[len(c)]:
                table[c].append(word)
                return

        # 沒放進去，只能放到全碼位上
        table[code].append(word)

    def put_into_dict(word, code, py, max_len=4):
        if len(word) == 1:
            put_into_dict_char(word, code, py, max_len)
        else:
            put_into_dict_word(word, code, py, max_len)        

    # 放入單字
    words = []
    for c in charset:
        for py in pinyin_table[c].keys():
            for ac in to_auxiliary_codes(c):
                try:
                    w = pinyin_weight(c, py)
                    words.append((w, c, to_double_pinyin(py)+ac, py))
                except:
                    traceback.print_exc()

    # 再放入詞語
    for (word, pinyin, weight) in read_input_dict():
        if len(word) > 1:
            try:
                code = encode_fixed_word(word, pinyin, False)
                assert len(code) == 4
                words.append((pinyin_weight(word, pinyin),
                              word,
                              code,
                              pinyin))
            except:
                traceback.print_exc()
                pass

    # 降序將所有字詞放入碼表
    words.sort(key=itemgetter(0), reverse=True)
    for (w, word, code, py) in words:
        put_into_dict(word, code, py)

    # 輸出碼表
    print_table(table)


def print_dict(dict, many_values):
    if many_values:
        for (key, list) in dict.items():
            print(f'{key}\t{" ".join(list)}')
    else:
        for (key, list) in dict.items():
            for el in list:
                print(f'{key}\t{el}')


def transpose_table(table):
    ret = defaultdict(list)
    for (k,vs) in table.items():
        for v in vs:
            ret[v].append(k)
    return ret


def print_table(table):
    if args.format == 'code-words':
        print_dict(table, True)
    elif args.format == 'code-word':
        print_dict(table, False)
    elif args.format == 'word-codes':
        print_dict(transpose_table(table), True)
    else:
        print_dict(transpose_table(table), False)



##################
## 詞庫維護例程 ##
##################
def handle_update_compact_dict():
    with open(args.rime_dict) as f:
        for l in f:
            l = l.rstrip('\n')
            matches = regex.findall(r'^([^\t]+)\t([a-z; ]*)(\t\d+)?', l)

            # Not a word
            if len(matches) == 0:
                print(l)
                continue

            [word, code, weight] = matches[0]
            weight = weight.strip()

            # No code means auto code. Do nothing.
            if len(code) == 0:
                print(l)
                continue
            
            sps = [fc.split(';')[0] for fc in code.split(' ')]
            acs = []
            for zi in word.replace("·", "").replace("，", ""):
                try:
                    acs.append(to_auxiliary_codes(zi)[0])
                except:
                    pass
            if len(acs) != len(sps):
                print('# BAD2:', l)
                continue

            # Now we just generate the new code
            newcode = ' '.join(sp + ';' + ac for (sp, ac) in zip(sps, acs))
            if weight:
                print(f'{word}\t{newcode}\t{weight}')
            else:
                print(f'{word}\t{newcode}')


def handle_update_char_weight():
    initialize_pinyin_table()
    with open(args.rime_dict) as f:
        for l in f:
            l = l.rstrip('\n')
            m = regex.match(r'^([^\t])\t([a-z][a-z];[a-z][a-z])\t(\d+)(.*)$', l)
            if not m:
                print(l)
            else:
                char = m[1]
                code = m[2]
                weight = int(m[3])
                comment = m[4]

                sp = code.split(';')[0]
                wt = pinyin_table.get(char, {})
                found = False
                for (py, w) in wt.items():
                    try:
                        if to_double_pinyin(py) == sp:
                            weight = w
                            found = True
                            break
                        else:
                            weight = 0
                    except:
                        weight = w

                if not found:
                    weight = 0

                print(f'{char}\t{code}\t{weight}{comment}')


def handle_update_sp():
    initialize_pinyin_table(skip_no_pinyin=True)
    with open(args.rime_dict) as f:
        for l in f:
            l = l.rstrip('\n')
            m = regex.match(r'^(\p{Han}\p{Han}+)\t([a-z; ]+)(.*)$', l)
            if not m:
                print(l)
                continue
            word = m[1]
            toreplace = False
            for c in word:
                if c in args.find:
                    toreplace = True
            if not toreplace:
                print(l)
                continue
            word_code = m[2].split(' ')
            rest = m[3]
            if len(word) != len(word_code):
                print(l)
                continue
            readings = list(pinyin_table[word].keys())
            if len(readings) != 1:
                print(l)
                continue
            real_reading = readings[0]
            real_word_sp = to_double_pinyin(real_reading).split(' ')
            word_aux = [ccode.split(';')[1] for ccode in word_code]
            word_code = ' '.join([csp+';'+caux for (csp, caux) in zip(real_word_sp, word_aux)])
            print(f'{word}	{word_code}{rest}')


def handle_convert_sp():
    def convert_word_sp(from_, to_, word_code):
        res = []
        for char_code in word_code.split(' '):
            [sp, aux] = char_code.split(';')
            if sp == 'pp':
                if args.special_code_policy == 'drop':
                    continue
                elif args.special_code_policy == 'keep':
                    pass
            else:
                sp = to_double_pinyin(from_double_pinyin(sp, from_), to_)
            res.append(sp + ';' + aux)
        return ' '.join(res)
    with open(args.rime_dict) as f:
        for l in f:
            l = l.rstrip('\n')
            m = regex.match(r'^(\p{Han}+)\t([a-z; ]+)(.*)$', l)
            if not m:
                print(l)
                continue
            word = m[1]
            code = convert_word_sp(args.double_pinyin, args.to, m[2])
            rest = m[3]
            print(f'{word}\t{code}{rest}')


def handle_convert_fixed_sp():
    with open(args.rime_dict) as f:
        for l in f:
            l = l.rstrip('\n')
            m = regex.match(r'^(\p{Han}+)\t([a-z]+)(.*)$', l)
            if not m:
                print(l)
                continue
            word = m[1]
            code = m[2]
            rest = m[3]
            # NOTE: 部分簡碼無法得到完整的雙拼形式，因此簡單地假設聲母部分不變，只需轉換韻母。
            # 該假設對小鶴轉換是成立的。
            if len(word) == 1 and len(code) > 1 and code[0] != 'o':  # 含有韻母的單字
                sp, aux = code[:2], code[2:]
                newsp = convert_sp1(sp, args.to)
                print(f'{word}\t{newsp + aux}{rest}')
            elif len(word) == 2 and len(code) == 4:  # 二字詞全碼
                sp1, sp2 = code[:2], code[2:]
                newsp1 = convert_sp1(sp1, args.to)
                newsp2 = convert_sp1(sp2, args.to)
                print(f'{word}\t{newsp1 + newsp2}{rest}')
            elif len(word) == 2 and len(code) == 3:  # 可能是簡碼，也可能是無理碼，直接略過
                continue
            elif len(word) == 3 and len(code) == 4:  # 三字詞全碼
                first2 = code[:2]
                last = code[2:]
                newlast = convert_sp1(last, args.to)
                print(f'{word}\t{first2 + newlast}{rest}')
            else:
                # 在上述假設下，其餘情況可原樣返回
                print(l)

    print('''# ⚠️ 請注意：機器轉換過程無法處理無理碼，這些編碼仍需手動處理（或刪除）''')


###############
### 程序入口 ###
###############
parser = argparse.ArgumentParser(
    prog='schemagen',
    description='Moran-like Rime schema+dictionary generator',
    epilog='This tool has Super Cow Powers'
)
parser.add_argument('--pinyin-table', default='data/pinyin.txt', help='拼音表')
parser.add_argument('--double-pinyin', choices=double_pinyin_choices, help='雙拼方案', default='zrm')
parser.add_argument('--auxiliary-code', choices=auxiliary_code_choices, help='輔助碼方案', default='zrm')
parser.add_argument('--auxiliary-code-fallback', help='若無輔助碼則使用該fallback', default='??')

subparsers = parser.add_subparsers(dest='command', required=True)

gen_chars = subparsers.add_parser('gen-chars', help='生成單字表')

gen_dict = subparsers.add_parser('gen-dict', help='生成詞庫')
gen_dict.add_argument('--input-dict', help='輸入txt格式詞庫', required=True)
gen_dict.add_argument('--opencc-for-pinyin', help='註音時的簡繁轉換，默認轉爲簡體', default='t2s.json')
gen_dict.add_argument('--opencc-for-output', help='輸出時的簡繁轉換，默認不使用 opencc')
gen_dict.add_argument('--compact', help='取消容錯碼', action='store_true', default=False)
gen_dict.add_argument('--no-freq', help='不產生詞頻', action='store_true', default=False)
gen_dict.add_argument('--freq-scale', help='詞頻縮放倍數', default=1.0)

gen_fixed = subparsers.add_parser('gen-fixed', help='生成簡碼碼表')
gen_fixed.add_argument('--charset', default='data/trad_chars.txt', help='常用單字表')
gen_fixed.add_argument('--input-dict', help='輸入txt格式詞庫', default='/Library/Input Methods/Squirrel.app/Contents/SharedSupport/essay.txt')
gen_fixed.add_argument('--opencc-for-pinyin', help='註音時的簡繁轉換，默認轉爲簡體', default='t2s.json')
gen_fixed.add_argument('--format', choices=['code-words', 'code-word', 'word-code', 'word-codes'], help='輸出碼表的格式', default='code-words')
gen_fixed.add_argument('--tolerance', help='每級簡碼最多可以容納多少候選', default='1,1,1')
gen_fixed.add_argument('--aabc', action='store_true', default=False, help='三碼字使用 AABC 方式編碼')
gen_fixed.add_argument('--short-word', action='store_true', help='生成簡詞', default=False)

update_compact_dict = subparsers.add_parser('update-compact-dict', help='更新 *compact* 詞庫中的輔助碼爲新輔助碼')
update_compact_dict.add_argument('--rime-dict', help='輸入rime格式詞庫（無frontmatter）', required=True)

update_char_weight = subparsers.add_parser('update-char-weight', help='更新 chars 詞庫中的詞頻')
update_char_weight.add_argument('--rime-dict', help='輸入rime格式詞庫', required=True)

update_sp = subparsers.add_parser('update-sp', help='根據原始數據重新修改詞的註音')
update_sp.add_argument('--rime-dict', help='輸入rime格式詞庫', required=True)
update_sp.add_argument('--find', help='只更新含有這些字的詞', default='重長彈阿拗扒蚌薄堡暴辟扁屏剝伯藏禪車稱澄匙臭畜伺攢大單提得都度囤革給合更谷檜巷和虹會奇緝茄嚼僥腳校芥矜勁龜咀殼烙僂綠落脈埋蔓氓秘繆弄瘧娜迫胖稽栖趄色塞厦折說數縮委省削血殷軋行')

convert_sp = subparsers.add_parser('convert-sp', help='轉換雙拼（整句詞庫）')
convert_sp.add_argument('--rime-dict', help='輸入rime格式詞庫', required=True)
convert_sp.add_argument('--to', choices=double_pinyin_choices, help='目的雙拼方案', required=True)
convert_sp.add_argument('--special-code-policy', choices=['keep', 'drop'], default='keep', help='特殊碼如何處理')

convert_fixed_sp = subparsers.add_parser('convert-fixed-sp', help='轉換雙拼（fixed碼表）')
convert_fixed_sp.add_argument('--rime-dict', help='輸入rime格式詞庫', required=True)
convert_fixed_sp.add_argument('--to', choices=double_pinyin_choices, help='目的雙拼方案', required=True)

if __name__ == '__main__':
    args = parser.parse_args()
    if args.command == 'gen-chars':
        handle_gen_chars()
    elif args.command == 'gen-dict':
        handle_gen_dict()
    elif args.command == 'gen-fixed':
        handle_gen_fixed()
    elif args.command == 'update-compact-dict':
        handle_update_compact_dict()
    elif args.command == 'update-char-weight':
        handle_update_char_weight()
    elif args.command == 'update-sp':
        handle_update_sp()
    elif args.command == 'convert-sp':
        handle_convert_sp()
    elif args.command == 'convert-fixed-sp':
        handle_convert_fixed_sp()
