#!/bin/bash
DIR="results"
# Fall back to paperresults if results/ is empty or missing
if [ -d "$DIR" ] && [ -n "$(ls -A $DIR 2>/dev/null)" ]; then
    python3 heatmap.py --save-heatmap --folder-to-aggregate $DIR
    cp aggregated.json $DIR
elif [ -d "paperresults" ]; then
    DIR="paperresults"
    python3 heatmap.py --save-heatmap --folder-to-aggregate $DIR
    cp aggregated.json $DIR
else
    echo "$DIR does not exist. Perform the unikraft syscall experiment first"
fi
