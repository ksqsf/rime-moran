# 简码码表问题太多了，不得不使用脚本批量检查

from radical import radical

with open('fixed.txt', 'r') as f:
    for l in f:
        l = l.strip()
        try:
            [code, char, *_] = l.strip().split('\t')
        except:
            continue
        if len(char) > 1:
            continue
        if len(code) < 3:
            continue

        assertions = [
            ('穴', 'x'),
            ('彳', 'x'),
            ('行', 'x'),
            ('目', 'o')
        ]

        for (rad, radc) in assertions:
            if rad == radical(char) and radc != code[2]:
                print(l)
