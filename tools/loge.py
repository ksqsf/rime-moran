# 更新落格输入法码表

import os
HOME = os.getenv("HOME")
loge_dir = HOME + "/Documents/落格输入法"
morj_txt = loge_dir + "/魔改自然码.txt"

start = False
with open('../moran_fixed.dict.yaml') as f:
    with open(morj_txt, 'w') as out:
        for l in f:
            l = l.strip()
            if not start and l == '...':
                start = True
            elif not start:
                pass
            else:
                try:
                    [code, txt, *_] = l.split('\t')
                    out.write(f'{txt}\t{code}\n')
                except:
                    pass
                
                
