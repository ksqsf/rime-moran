#!/bin/bash

STRICT="$1"

echo Strict about errors? $STRICT

compact_dicts=(
    "../moran.essay.dict.yaml"
    "../moran.tencent.dict.yaml"
    "../moran.moe.dict.yaml"
    "../moran.thuocl.dict.yaml"
)

UPDATE_LINE_RE=$'^.+\t'

set -x

# Extract the words from foo.dict.yaml into foo.in.
extract_dict() {
    DICT_FILE="$1"
    HEADER_FILE="$2"
    BODY_FILE="$3"

    grep -E "$UPDATE_LINE_RE" "$DICT_FILE" > "$BODY_FILE"
    grep -v -E "$UPDATE_LINE_RE" "$DICT_FILE" > "$HEADER_FILE"
}

update_compact_dict() {
    DICT_FILE="$1"
    HEADER_FILE="${DICT_FILE%.dict.yaml}.header"
    INPUT_FILE="${DICT_FILE%.dict.yaml}.in"
    OUTPUT_FILE="${DICT_FILE%.dict.yaml}.out"

    extract_dict "$DICT_FILE" "$HEADER_FILE" "$INPUT_FILE"
    python3 schemagen.py update-compact-dict --rime-dict="$INPUT_FILE" > "$OUTPUT_FILE"

    if grep '^# BAD' "$OUTPUT_FILE"
    then
        echo '!!! BAD DICT !!!'

        # Still allow grep to show bad entries.
        if [ x$STRICT = x"yes" ]; then
            rm -f $INPUT_FILE $HEADER_FILE
            return 1
        else
            cat "$HEADER_FILE" "$OUTPUT_FILE" > "$DICT_FILE"
            rm -f $INPUT_FILE $HEADER_FILE $OUTPUT_FILE
            return 0
        fi
    else
        cat "$HEADER_FILE" "$OUTPUT_FILE" > "$DICT_FILE"
        rm -f $INPUT_FILE $HEADER_FILE $OUTPUT_FILE
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
