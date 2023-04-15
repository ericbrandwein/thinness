if [ "$#" -ne 1 ]; then
    python -m cProfile -o thinness.prof calculate_thinness.py
else
    python -m cProfile -o thinness.prof calculate_thinness.py "$1"
fi
snakeviz -b chromium thinness.prof