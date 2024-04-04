# gen_chai_filter.py
# 生成拆分濾鏡數據

from collections import defaultdict

chaidb = defaultdict(dict)
with open('data/moran_chai.txt', 'r') as f:
    for l in f:
        if l == '\n' or l.startswith('#'):
            continue
        [char, code, chai] = l.strip().split(' ')
        chaidb[char][code] = chai

cur = []

def print_and_clear():
    global cur
    if len(cur) == 0:
        return
    res = ''
    for (char, code, chai) in cur:
        res += '〔' + chai + code + '〕'
    print(f'{cur[0][0]}\t{res}')
    cur = []

# Use zrmdb as the source of truth to preserve order.
with open('data/zrmdb.txt', 'r') as f:
    for l in f:
        [char, code] = l.strip().split(' ')
        chai = chaidb[char].get(code, '.')
        if len(cur) > 0 and cur[0][0] != char:
            print_and_clear()
        cur.append((char, code, chai))
    if len(cur) > 0:
        print_and_clear()
