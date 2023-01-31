#!/usr/bin/env python3

'''
給 Rime 碼表單字添加字頻數據。

原始字頻數據是簡體字的，故而需要一個辦法調和這個問題。

第一步：分配字頻

1. 如果 A 字和 B 字是異體字或簡繁關係，那麼 A 和 B 放在同一個等價類中。
2. 規定：同一個等價類中的字具有相同的權重，這個等價類的字頻是其中所有字的字頻之和。
3. 規定：字頻空間離散化爲 N 等，每個等級具有固定的權重。
4. 將所有等價類根據其字頻分配到這 N 等中，稱爲基準權重 W。

上述分配過程不考慮實際編碼，僅考慮字本身。

第二步：根據字音相對分配權重。字音相對頻率數據來自於朙月拼音碼表。

設某等價類中一個字具有 n 個讀音，分別是 p[1..n]，頻率分別是 f[1..n]。
則 p[i] 對應的權重被線性修正爲 W * f[i]。
如果表中沒有該讀音數據，則賦予權重 0。
'''

from zrmify import zrmify
from typing import Set, Dict, List, Tuple
import opencc


conv = opencc.OpenCC()  # 默認：轉繁爲簡


N_LEVELS = 1000
MAX_WEIGHT = 1000000
level_to_weight = list(MAX_WEIGHT // N_LEVELS * i for i in range(N_LEVELS))


class Char:
    def __init__(self, ch: str):
        self.char = ch
        self.parent = self
        self.codes: Set[str] = set()
        self.frequency: float = 0.0

    def add_code(self, code: str):
        self.codes.add(code)

    def union(self, other: 'Char'):
        root = other.parent
        while root is not root.parent:
            root = root.parent
        self.parent = root
        other.parent = root

    def root(self) -> 'Char':
        root = self.parent
        while root is not root.parent:
            root = root.parent
        self.parent = root
        return root

    def add_frequency(self, freq: float):
        '''把 freq 加到 root 上.'''
        self.root().frequency += freq

    def level(self, thresholds: List[float]):
        for l, threshold in reversed(list(enumerate(thresholds))):
            if self.root().frequency >= threshold:
                return l
        return 0


class FrequencyTable:
    def __init__(self, path: str) -> None:
        '''文件格式：
        字1,字頻1
        字2,字頻2
        ...

        字頻須是整數，並且字沒有重複。
        '''
        self.table: Dict[str, int] = dict()
        with open(path, 'r') as f:
            for line in f:
                [ch, freq] = line.split(',')
                freq = int(freq)
                self.table[ch] = int(freq)

    def __getitem__(self, ch) -> int:
        return self.table.get(ch, 0)


class PronunciationTable:
    def __init__(self, path: str) -> None:
        # relative_frequency = table[char][reading]
        self.table: Dict[Tuple[str,str], float] = dict()

        with open(path, 'r') as f:
            for line in f:
                line = line.strip()
                if line == '' or line.startswith('#'):
                    continue
                [char, reading, *freq] = line.split("\t")
                if len(freq) == 0:
                    continue
                reading = zrmify(reading)
                freq = freq[0]
                if freq == '0':
                    self.table[(char, reading)] = 0.0
                else:
                    self.table[(char, reading)] = float(freq[:freq.find('%')]) * 0.01

    def __getitem__(self, pair: Tuple[str,str]) -> float:
        return self.table.get(pair, 1.0)


class CharSet:
    '''記錄字集信息'''
    def __init__(self):
        self.chars: Dict[str, Char] = dict()

    def get(self, ch: str) -> Char:
        if ch not in self.chars:
            self.chars[ch] = Char(ch)
        return self.chars[ch]

    def add_mapping(self, ch: str, code: str):
        '''記錄一個新映射，並把 ch 與可能相關的字關聯起來.'''
        char = self.get(ch)
        char.add_code(code)
        schar = self.get(conv.convert(ch))
        char.union(schar)

    def load_table(self, path: str):
        with open(path, 'r') as f:
            for line in f:
                [ch, code, *_] = line.split()
                self.add_mapping(ch, code)

    def process_frequency(self, ft: FrequencyTable):
        for char in self.chars.values():
            char.add_frequency(ft[char.char])

        # Now, collect all frequencies.
        freqs = set()
        for char in self.chars.values():
            freqs.add(char.root().frequency)

        # Find the threshold for each level.
        freqs = list(freqs)
        freqs.sort()
        n = len(freqs)
        thresholds = []
        for i in range(N_LEVELS):
            thresholds.append(freqs[n // N_LEVELS * i])
        self.thresholds = thresholds

    def export(self, path: str, pt: PronunciationTable):
        with open(path, 'w') as f:
            for char in self.chars.values():
                w = level_to_weight[char.level(self.thresholds)]
                for code in char.codes:
                    reading = code.split(';')[0]
                    f.write(f'{char.char}\t{code}\t{int(w * pt[(char.char, reading)])}\n')


if __name__ == '__main__':
    # 字頻數據來自 https://faculty.blcu.edu.cn/xinghb/zh_CN/article/167473/content/1437.htm
    cs = CharSet()
    ft = FrequencyTable('freq.csv')
    pt = PronunciationTable('luna_pinyin.dict.yaml')
    cs.load_table('zrm.in')
    cs.process_frequency(ft)
    cs.export('zrm.out', pt)
