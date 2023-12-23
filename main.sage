#!/usr/bin/env sage

from thinness import fill_csvs_paralelly
import os

for n in range(10, 21):
    fill_csvs_paralelly(n)
    os.remove('data/last-processed.index')

