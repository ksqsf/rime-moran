#!/usr/bin/env python3
import argparse
import opencc
import os
from collections import defaultdict
import re


class FakeOpenCC:
    def convert(text):
        return text


class Table:
    def __init__(self):
        self.w2c = defaultdict(list)
        self.c2w = defaultdict(list)

    def get_long_code(self, word):
        for code in self.w2c[word]:
            if len(code) >= 2:
                return code
        raise KeyError(f'{word} 無長碼, codes = {self.w2c[word]}')

    def has_quick_code(self, word, code):
        all_codes = self.w2c[word]
        for c in all_codes:
            if code.startswith(c) and len(c) < 4:
                return True
        return False

    def add(self, word, code, w=0):
        if not code:
            try:
                code = self.encode(word)
            except KeyError as e:
                print('# 無法編碼 %s : %s' % (word, str(e)))
                return
        if self.has_quick_code(word, code):
            # print('讓全', word, code)
            w = -1
        self.w2c[word].append(code)
        self.c2w[code].append((word, w))
        self.c2w[code].sort(key=lambda pair: pair[1], reverse=True)
        # if len(word)== 3:
        #     print('added %s %s' % (word, code))

    def encode(self, word):
        if len(word) == 1:
            raise KeyError('無碼單字: %s' % word)
        elif len(word) == 2:
            return self.get_long_code(word[0])[:2] + self.get_long_code(word[1])[:2]
        elif len(word) == 3:
            return self.get_long_code(word[0])[0] + self.get_long_code(word[1])[0] + self.get_long_code(word[2])[:2]
        else:
            return self.get_long_code(word[0])[0] + self.get_long_code(word[1])[0] + self.get_long_code(word[2])[0] + self.get_long_code(word[-1])[0]

    def print_c2w(self, file):
        for code, pairs in self.c2w.items():
            words = [pair[0] for pair in pairs]
            print(code + '\t' + '\t'.join(words), file=file)

    def print_w2c(self, file):
        for word, codes in self.w2c.items():
            for code in codes:
                print(f'{word}	{code}')


def make_opencc(config):
    if not config:
        return FakeOpenCC()
    cwd = os.getcwd()
    os.chdir('../opencc/')
    cc = opencc.OpenCC(config)
    os.chdir(cwd)
    return cc

table = Table()

def main(args):
    cc = make_opencc(args.opencc)
    global table

    # fixed table
    with open(args.dict, 'r') as f:
        deferred = []
        for l in f:
            l = l.rstrip("\n")
            try:
                matches = re.findall(r'^([^\t]+)\t([a-z;]+)\t?([a-z]+)?', l)
                if matches:
                    word, code, stem = matches[0]
                    if stem:
                        # stem should be added at the end of the list of codes of this char
                        deferred.append((word, stem))
                else:
                    matches = re.findall(r'^\w+$', l)
                    if not matches: continue
                    word = matches[0]
                    code = None
                word = cc.convert(word)
                table.add(word, code)
            except ValueError:
                print("Error reading line: " + l)
        for (word, stem) in deferred:
            table.add(word, stem)

    # additional chars
    with open('../moran.chars.dict.yaml', 'r') as f:
        for l in f:
            matches = re.findall(r'(\w+)	([a-z]+;[a-z]+)	(\d+)', l)
            if not matches: continue
            char, code, w = matches[0]
            w = int(w)
            table.add(char, ''.join(code.split(';')) + 'o', w)

    # liangfen
    with open('../zrlf.dict.yaml', 'r') as f:
        for l in f:
            matches = re.findall(r'(\w+)	([a-z]+)', l)
            if not matches: continue
            char, code = matches[0]
            table.add(char, 'olf' + code)

    # bihua
    with open('/Library/Input Methods/Squirrel.app/Contents/SharedSupport/stroke.dict.yaml') as f:
        for l in f:
            matches = re.findall(r'(\w+)	([a-z]+)', l)
            if not matches: continue
            char, code = matches[0]
            table.add(char, 'obh' + code)

    # 拆分表
    with open('../opencc/moran_chaifen.txt', 'r') as f:
        for l in f:
            [zi, chai] = l.strip().split('\t')
            table.add(zi, '拆分：' + chai)

    with open('dazhu.txt', 'w') as f:
        table.print_c2w(f)
        # table.print_w2c(f)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dict', default='../moran_fixed.dict.yaml', help='簡碼碼表文件')
    parser.add_argument('--opencc', '-c',
                        default='moran_t2s.json',
                        help='轉換詞表（空表示不轉換）')
    args = parser.parse_args()
    main(args)
