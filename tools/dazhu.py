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
        raise KeyError('%s 無長碼' % word)

    def add(self, word, code):
        if not code:
            try:
                code = self.encode(word)
            except KeyError as e:
                print('# 無法編碼 %s : %s' % (word, str(e)))
                return
        self.w2c[word].append(code)
        self.c2w[code].append(word)
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
        for code, words in self.c2w.items():
            print(code + '\t' + '\t'.join(words), file=file)


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
    with open('../moran_fixed.dict.yaml', 'r') as f:
        for l in f:
            matches = re.findall(r'^(\w+)	([a-z]+)', l)
            if matches:
                word, code = matches[0]
            else:
                matches = re.findall(r'^\w+$', l)
                if not matches: continue
                word = matches[0]
                code = None
            word = cc.convert(word)
            table.add(word, code)

    # additional chars
    with open('../moran.chars.dict.yaml', 'r') as f:
        for l in f:
            matches = re.findall(r'(\w+)	([a-z]+;[a-z]+)', l)
            if not matches: continue
            char, code = matches[0]
            table.add(char, ''.join(code.split(';')) + 'o')

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

    with open('dazhu.txt', 'w') as f:
        table.print_c2w(f)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--opencc', '-c',
                        default='moran_t2s.json',
                        help='轉換詞表（空表示不轉換）')
    args = parser.parse_args()
    main(args)
