# 之前简码分配写得有点问题，一开始是只分配到3码上，后来也加上4码，结果忘了字频处理有问题了。。。
# 现在重新修复之。。。

# 1. 对于每个前缀 xyz 的码，找出 xyz 对应的所有单字
# 2. 按字频排序 xyz 对应的所有字
# 3. 把 xyz 赋予最高频的这个字，然后其他字依次给予全码

from collections import defaultdict

mappings = defaultdict(list)
cnt = 0
reorder = defaultdict(list)
old_pos = dict()

# 读取码表，记录 xyz[w] 的单字到 reorder 中
with open('../backup', 'r') as f:
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
        [code, txt] = l.split()
        if len(txt) >= 2 or len(code) < 3:
            # 不需要特别处理的
            mappings[code].append(txt)
        elif len(code) >= 3:
            # 单字并且是3码以上
            # 为了保证字和词的相对顺序不变（只改变字的顺序），用cnt给每个被替换的汉字一个唯一的标识符
            # mappings[code].append(cnt)
            reorder[code[:3]].append((txt, cnt))
            old_pos[(txt, cnt)] = cnt
            cnt += 1


# 每个 reorder 分组里都重新排序
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
new_pos = dict()
from zrmstd import *
def get_code(c, prefix):
    specialchars = {
        '咡': ['ty', 'er'],
        '朮': ['vu'],
    }
    if c in specialchars:
        ups = specialchars[c]
    else:
        ups = zrmups(c)
    ups = [up for up in ups if up.startswith(prefix[:2])]
    if len(ups) == 0:
        print(c, prefix, zrmups(c))
    std = zrmstd(c)
    return ups[0] + std
for (prefix, cands) in reorder.items():
    indices = [ old_pos[c] for c in cands ]
    cands.sort(key=lambda c: -ft[cc.convert(c[0])])
    for i, c in enumerate(cands):
        # new_pos[i] = c[0]
        code = get_code(c[0], prefix)
        if i == 0:
            print('添加三码：' + code[:3])
            mappings[code[:3]].append(c[0])
        else:
            mappings[code].append(c[0])
# 这个比较仍然有点问题：
# 比如 uum 的首选会是 ('朮', 9505)，不过这种情况只能手动调整了


# 输出结果
f = open('../moran_fixed.dict.yaml', 'w')
f.write('''# Rime dictionary
# encoding: utf-8

---
name: moran_fixed
version: "1"
sort: original
columns:
  - code
  - text
...

''')
for (code, cands) in mappings.items():
    for cand in cands:
        f.write(f'{code}\t{cand}\n')
