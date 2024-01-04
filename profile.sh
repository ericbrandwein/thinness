#!/bin/bash
PROFILE_FILE=$1.prof
python -m cProfile -o $PROFILE_FILE -m $1 && snakeviz $PROFILE_FILE