import opencc
from char_freq import FrequencyTable


t2s = opencc.OpenCC('t2s.json').convert
s2t = opencc.OpenCC('s2t.json').convert
ft = FrequencyTable('freq.csv')


entries = []


with open('../moran.main.dict.yaml', 'r') as f:
    flag = False
    for l in f:
        l = l.strip()
        if not flag and l == '#----------':
            flag = True
            continue
        if flag and l == '#----------':
            break
        if not flag:
            continue
        [char, code, _w] = l.split()
        entries.append((char, code))


with open('output.txt', 'w') as f:
    for (char, code) in entries:
        # 如果是一對一簡化字
        if s2t(t2s(char)) == char:
            w = ft[t2s(char)]
        else:
            w = ft[char]
        # 如果是简化字，相应地减少其权重
        if t2s(char) == char:
            w = max(0, w - 100)
        f.write(f'{char}\t{code}\t{w}\n')
