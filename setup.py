from setuptools import setup, Extension
from Cython.Build import cythonize

setup(
    ext_modules=cythonize("z3_thinness.pyx")
)