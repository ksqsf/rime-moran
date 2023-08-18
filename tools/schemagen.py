#!/usr/bin/env python3
import argparse
from collections import *
from itertools import *
import zrmify
import flypyify
import pandas
import math
import opencc
from pypinyin import lazy_pinyin
from operator import *
import regex


double_pinyin_choices = ['zrm', 'flypy']
assistive_code_choices = ['zrm', 'hanxin']

args = None
assistive_table = defaultdict(list)
essay_table = defaultdict(int)
luna_table = OrderedDict()
luna_pinyin_table = defaultdict(list)
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


def to_double_pinyin(pinyin):
    global args
    match args.double_pinyin:
        case 'zrm':
            return zrmify.zrmify(pinyin)
        case 'flypy':
            return flypyify.flypyify(pinyin)
    raise ValueError('Unknown double pinyin ' + args.double_pinyin)


def to_assistive_codes(char):
    global assistive_table
    if not assistive_table:
        match args.assistive_code:
            case 'zrm':
                assistive_table = read_txt_table('data/zrmdb.txt')
            case 'hanxin':
                assistive_table = read_txt_table('data/hanxindb.txt')
            case _:
                raise ValueError('Unknown assistive code ' + args.assistive_code)
    return assistive_table[char]


def essay_weight(char, default=0):
    if not essay_table:
        with open(args.essay_txt, 'r') as f:
            for line in f:
                [char, freq, *_] = line.strip().split()
                freq = int(freq)
                essay_table[char] = freq
    return essay_table.get(char, default)


def initialize_luna_table():
    with open(args.luna_pinyin_dict, 'r') as f:
        # skip over "..."
        for line in f:
            if line.strip() == '...':
                break
        # iterate over the luna pinyin dict
        for line in f:
            line = line.strip()
            try:
                [word, pinyin, *percentage_str] = line.split('\t')
            except:
                continue
            if len(word) > 1:
                continue

            if len(percentage_str) == 0:
                percentage = 1.0
            elif percentage_str[0] in ['0', '0%']:
                percentage = 0.0
            else:
                assert percentage_str[0][-1] == '%'
                percentage = float(percentage_str[0][:-1]) / 100.0

            weight = math.ceil(essay_weight(word) * percentage)
            luna_table[(word, pinyin)] = weight
            luna_pinyin_table[word].append(pinyin)


def luna_weight(char, pinyin, default=0):
    if not luna_table:
        initialize_luna_table()
    return luna_table.get((char, pinyin), default)


def iter_char_codes(char, pinyin):
    try:
        double_pinyin = to_double_pinyin(pinyin)
        assistive_codes = to_assistive_codes(char) or [args.assistive_code_fallback]
        yield from (double_pinyin + ';' + ac for ac in assistive_codes)
    except:
        yield from iter([])


def char_codes(char, pinyin):
    if 'compact' in args and args.compact:
        return [next(iter_char_codes(char, pinyin))]
    else:
        return list(iter_char_codes(char, pinyin))


def handle_gen_chars():
    initialize_luna_table()
    for ((char, pinyin), weight) in luna_table.items():
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
    if args and args.opencc_for_pinyin:
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
                print(line)
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
                weight = luna_weight(word, pinyin) or essay_weight(word)
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


def encode_fixed_word(word, pinyin=None):
    assert len(word) > 1
    if not pinyin:
        pinyin = word_to_pinyin(word)
    double_pinyin = to_double_pinyin(pinyin).split()
    if len(word) == 2:
        return ''.join(double_pinyin)
    elif len(word) == 3:
        return double_pinyin[0][0] + double_pinyin[1][0] + double_pinyin[2]
    else:
        return double_pinyin[0][0] + double_pinyin[1][0] + double_pinyin[-2][0] + double_pinyin[-1][0]


def handle_gen_fixed():
    initialize_charset()
    initialize_luna_table()

    table = defaultdict(list)
    encoded = defaultdict(list)
    def put_into_dict(word, code, max_len=4):
        nonlocal table, encoded
        # 詞總是使用四碼
        if len(word) > 1:
            table[code].append(word)
            return
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

    # 放入單字
    words = []
    for c in charset:
        for py in luna_pinyin_table[c]:
            for ac in to_assistive_codes(c):
                try:
                    words.append((luna_weight(c, py), c, to_double_pinyin(py)+ac))
                except:
                    continue

    # 再放入詞語
    for (word, pinyin, weight) in read_input_dict():
        if len(word) > 1:
            try:
                words.append((essay_weight(word), word, encode_fixed_word(word, pinyin)))
            except:
                continue

    # 降序將所有字詞放入碼表
    words.sort(key=itemgetter(0), reverse=True)
    for (_, word, code) in words:
        put_into_dict(word, code)

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


###############
### 程序入口 ###
###############
parser = argparse.ArgumentParser(
    prog='schemagen',
    description='Moran-like Rime schema+dictionary generator',
    epilog='This tool has Super Cow Powers'
)
parser.add_argument('--essay-txt', default='/Library/Input Methods/Squirrel.app/Contents/SharedSupport/essay.txt', help='essay.txt 路徑')
parser.add_argument('--luna-pinyin-dict', default='/Library/Input Methods/Squirrel.app/Contents/SharedSupport/luna_pinyin.dict.yaml', help='luna_pinyin.dict.yaml 路徑')
parser.add_argument('--double-pinyin', choices=double_pinyin_choices, help='雙拼方案', default='zrm')
parser.add_argument('--assistive-code', choices=assistive_code_choices, help='輔助碼方案', default='zrm')
parser.add_argument('--assistive-code-fallback', help='若無輔助碼則使用該fallback', default='??')

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

if __name__ == '__main__':
    args = parser.parse_args()
    if args.command == 'gen-chars':
        handle_gen_chars()
    elif args.command == 'gen-dict':
        handle_gen_dict()
    elif args.command == 'gen-fixed':
        handle_gen_fixed()
