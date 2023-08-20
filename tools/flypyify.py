#/usr/bin/env python3

# flypyify.py -- 把拼音（字符串）轉換成小鶴雙拼（字符串）
#
# Copyright (c) 2023  ksqsf
# License: MIT License

'''
把拼音（字符串）轉換成小鶴雙拼（字符串）。
'''

def flypyify(pinyin: str) -> str:
    '''將空白分隔的拼音序列轉換爲等價的小鶴雙拼，結果以空格分隔。'''
    pinyins = pinyin.split()
    return ' '.join(map(flypyify1, pinyins))

def flypyify1(pinyin: str) -> str:
    '''將一個有效的拼音序列轉換爲等價的小鶴雙拼。'''
    assert len(pinyin) > 0
    if pinyin[0] in 'aeiou':
        return 零聲母轉換(pinyin)
    elif pinyin == 'n':
        return 'en'
    elif len(pinyin) > 2 and pinyin[:2] in ['zh', 'ch', 'sh']:
        聲 = 聲母轉換(pinyin[:2])
        韻 = 韻母轉換(pinyin[2:])
        return 聲 + 韻
    else:
        聲 = 聲母轉換(pinyin[:1])
        韻 = 韻母轉換(pinyin[1:])
        return 聲 + 韻

def 零聲母轉換(pinyin: str) -> str:
    if len(pinyin) == 2:
        return pinyin
    elif len(pinyin) == 1:
        return pinyin * 2
    else:
        match pinyin:
            case 'ang': return 'ah'
            case 'eng': return 'eg'
            case _: raise ValueError('無效零聲母拼音序列: ' + pinyin)

def 聲母轉換(pinyin: str) -> str:
    match pinyin:
        case 'zh': return 'v'
        case 'ch': return 'i'
        case 'sh': return 'u'
        case _:
            if pinyin in 'bpmfdtnlgkhjqxrzcsyw':
                return pinyin
            else:
                raise ValueError('無效拼音聲母序列: ' + pinyin)

def 韻母轉換(pinyin: str) -> str:
    映射表 = {
        'a': 'a', 'o': 'o', 'e': 'e', 'i': 'i', 'u': 'u', 'v': 'v',
        'ai': 'd', 'ei': 'w', 'ui': 'v', 'ao': 'c', 'ou': 'z', 'iu': 'q',
        'ie': 'p', 've': 't', 'ue': 't', 'an': 'j', 'en': 'f', 'in': 'b',
        'un': 'y',
        'ang': 'h', 'eng': 'g', 'ing': 'k', 'ong': 's',
        'ia': 'x', 'iao': 'n', 'ian': 'm', 'iang': 'l', 'iong': 's',
        'ua': 'x', 'uo': 'o', 'uai': 'k', 'uan': 'r', 'uang': 'l'
    }
    if pinyin in 映射表:
        return 映射表[pinyin]
    else:
        raise ValueError('無效拼音韻母序列: ' + pinyin)
