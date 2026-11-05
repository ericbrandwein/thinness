cimport cython
from libc.stdint cimport uint64_t
from sage.data_structures.bitset_base cimport bitset_t


@cython.final
cdef class SeenStates:
    cdef size_t words
    cdef int max_parts
    cdef int sets_per_part
    cdef size_t key_words
    cdef size_t max_size
    cdef size_t size
    cdef size_t capacity
    cdef uint64_t* slots
    cdef uint64_t* key
    cdef uint64_t* part_key

    cdef bint contains_or_add(
        self,
        bitset_t suffix_vertices,
        bitset_t* part_sets,
        int parts_used,
    ) noexcept
    cdef bint contains_or_add_words(
        self,
        uint64_t suffix_vertices,
        uint64_t* part_sets,
        int parts_used,
    ) noexcept
    cdef bint _contains_or_add_key(self) noexcept
    cdef uint64_t* _find_slot(
        self,
        uint64_t* slots,
        size_t capacity,
        uint64_t hash,
        uint64_t* key,
    ) noexcept
    cdef bint _grow(self) noexcept
