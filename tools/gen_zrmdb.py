import re
from collections import defaultdict

DATA_LINE_RE = re.compile(r'^(.)\t[a-z]+;([a-z][a-z])')
table = defaultdict(list)

with open('../moran.chars.dict.yaml', 'r') as f:
    for l in f:
        if m := re.match(DATA_LINE_RE, l):
            char = m[1]
            code = m[2]
            if code not in table[char]:
                table[char].append(code)

for (char, codes) in table.items():
    for code in codes:
        print(f'{char} {code}')
