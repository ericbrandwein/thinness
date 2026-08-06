#!/bin/bash
PROFILE_FILE=$1.prof
python -m cProfile -o $PROFILE_FILE $1 && snakeviz -H 0.0.0.0 -s $PROFILE_FILE
