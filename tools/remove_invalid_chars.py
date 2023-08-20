#!/usr/bin/env python3
# Author: ksqsf
# Released into the Public Domain

import sys
import re


re_chinese = re.compile('[\u4e00-\u9fff\u3400-\u4dbf\U00020000-\U0002a6df\U0002a700-\U0002ebef\U00030000-\U000323af\ufa0e\ufa0f\ufa11\ufa13\ufa14\ufa1f\ufa21\ufa23\ufa24\ufa27\ufa28\ufa29\u3006\u3007][\ufe00-\ufe0f\U000e0100-\U000e01ef]?')


def remove_invalid_chars(s):
    return ''.join(re_chinese.findall(s))


if __name__ == '__main__':
    for line in sys.stdin:
        result = remove_invalid_chars(line)
        if len(result) < 2:
            continue
        else:
            print(result)
