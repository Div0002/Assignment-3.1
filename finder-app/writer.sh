#!/bin/sh

if [ $# -ne 2 ]; then
    echo "Error: Two arguments required: <writefile> <writestr>"
    exit 1
fi

writefile="$1"
writestr="$2"

dir=$(dirname "$writefile")

if ! mkdir -p "$dir"; then
    echo "Error: Could not create directory path"
    exit 1
fi

if ! echo "$writestr" > "$writefile"; then
    echo "Error: Could not create or write file"
    exit 1
fi
