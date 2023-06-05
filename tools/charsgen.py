# 根据字频，生成初始化简码
# 注意: 这个文件已经没用了。以后直接修改 moran_fixed.dict.yaml 即可

# 字集取 常用國字標準字體表 和 次常用國字標準字體表, ~1w字
def load_charset(path):
    res = []
    with open(path) as f:
        for l in f:
            if l.startswith('#'):
                continue
            char = l.strip().split()[0]
            res.append(char)
    return res


charset = load_charset('data/trad_chars.txt')


# 把已经有编码的字排除掉
has_code = []
existing_codes = set()

with open('../moran_fixed_primary.dict.yaml') as f:
    started = False
    for l in f:
        l = l.strip()
        if l == '' or l.startswith('#'):
            continue
        if l == '...':
            started = True
            continue
        if not started:
            continue
        txt = l.split()[1]
        existing_codes.add(l.split()[0])
        has_code.append(txt)


to_encode = set(charset) - set(has_code)


# 对于每个所有剩下的字:
#   - 尝试 yyx，如果是空的，那就放在这里
#   -          如果非空，就放到 yyxx 里
from collections import defaultdict
from zrmstd import *
mappings = defaultdict(list)
for char in to_encode:
    for up in zrmups(char):
        try:
            f = zrmstd(char)
            code = up+f[0]
            if len(mappings[code]) == 0 and code not in existing_codes:
                mappings[code].append(char)
            else:
                mappings[up+f].append(char)
        except:
            mappings[None].append(char)


# 3. 三码位置按字频排序
import opencc
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
ft = FrequencyTable('freq.csv')
cc = opencc.OpenCC('t2s.json')
for cands in mappings.values():
    cands.sort(key=lambda c: -ft[cc.convert(c)])


# 4. 输出结果
for (code, cands) in mappings.items():
    if code is None:
        print('# 无法处理: ' + str(" ".join(cands)))
    else:
        for cand in cands:
            print(f'{code}\t{cand}')
