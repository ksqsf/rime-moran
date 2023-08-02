# quick access to essay.txt

from collections import defaultdict

essay_data = defaultdict(int)
with open('/Library/Input Methods/Squirrel.app/Contents/SharedSupport/essay.txt') as f:
    for line in f:
        line = line.strip()
        [txt, w] = line.split('\t')
        essay_data[txt] = int(w)


def essay_weight(word):
    return essay_data[word]
