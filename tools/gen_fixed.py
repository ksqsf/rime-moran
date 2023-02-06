import itertools

alphabet = 'abcdefghjiklmnopqrstuvwxyz'

# 一簡
for a in alphabet:
    print(f'#{a}')

# 二簡
for (a, b) in itertools.product(alphabet, alphabet):
    print(f'#{a}{b}')

# 三簡
for (a, b, c) in itertools.product(alphabet, alphabet, alphabet):
    print(f'#{a}{b}{c}')
