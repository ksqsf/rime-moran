# scale weights in [0,1000000] to [0,1]

import sys

for l in sys.stdin:
    [text, code, weight] = l.split("\t")
    print(f'{text}\t{code}\t{int(weight) / 1000000:g}')
