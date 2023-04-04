# scale weights in [0,1000000] to [0,1]
# or reverse

import sys

for l in sys.stdin:
    [text, code, weight] = l.split("\t")
    print(f'{text}\t{code}\t{float(weight) / 1000000:g}')
