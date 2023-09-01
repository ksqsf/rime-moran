# Generate pinyin.txt from essay.raw and luna.raw
# CC0

from collections import defaultdict

essay_table = defaultdict(int)
luna_table = defaultdict(list)

with open('essay.raw', 'r') as f:
    for line in f:
        line = line.strip()
        [word, freq] = line.split('\t')
        essay_table[word] = int(freq)


with open('luna.raw', 'r') as f:
    for line in f:
        line = line.strip()
        [word, pinyin, *pc] = line.split('\t')
        if len(pc) == 0:
            f = 1.0
        else:
            f = float(pc[0][:-1]) / 100
        w = essay_table[word] * f
        luna_table[word].append((pinyin, int(w)))

only_in_essay = set(essay_table.keys()) - set(luna_table.keys())

with open('pinyin.txt', 'w') as f:
    for (word, pairs) in luna_table.items():
        for (pinyin, w) in pairs:
            f.write(f'{word}\t{pinyin}\t{w}\n')

    for word in only_in_essay:
        f.write(f'{word}\t\t{essay_table[word]}\n')
