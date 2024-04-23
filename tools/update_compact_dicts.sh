#!/bin/bash

STRICT="$1"

echo Strict about errors? $STRICT

if [ -d ../.venv ]; then
    source ../.venv/bin/activate
fi

compact_dicts=(
    "../moran.base.dict.yaml"
    "../moran.tencent.dict.yaml"
    "../moran.moe.dict.yaml"
)

UPDATE_LINE_RE=$'^.+\t'

set -x

update_compact_dict() {
    DICT_FILE="$1"
    INPUT_FILE="${DICT_FILE%.dict.yaml}.in"
    OUTPUT_FILE="${DICT_FILE%.dict.yaml}.out"

    cp $DICT_FILE $INPUT_FILE
    python3 schemagen.py update-compact-dict --rime-dict="$INPUT_FILE" > "$OUTPUT_FILE"

    if grep '^# BAD' "$OUTPUT_FILE"
    then
        echo '!!! BAD DICT !!!'

        # Still allow grep to show bad entries.
        if [ x$STRICT = x"yes" ]; then
            rm -f $INPUT_FILE
            return 1
        else
            mv $OUTPUT_FILE $DICT_FILE
            rm -f $INPUT_FILE $OUTPUT_FILE
            return 0
        fi
    else
        mv $OUTPUT_FILE $DICT_FILE
        rm -f $INPUT_FILE $OUTPUT_FILE
        return 0
    fi
}

for dict in "${compact_dicts[@]}"; do
    echo ""
    echo "* Updating $dict"
    if update_compact_dict "$dict"
    then
        echo "  success"
    else
        echo "  ERROR!"
    fi
done
