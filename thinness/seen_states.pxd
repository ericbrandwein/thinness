cimport cython
from sage.data_structures.bitset_base cimport bitset_t
from sage.libs.gmp.types cimport mp_limb_t


@cython.final
cdef class SeenStates:
    cdef size_t limbs
    cdef int max_parts
    cdef size_t key_limbs
    cdef size_t max_size
    cdef size_t size
    cdef size_t capacity
    cdef mp_limb_t* slots
    cdef mp_limb_t* key

    cdef bint contains_or_add(
        self,
        bitset_t suffix_vertices,
        bitset_t* part_suffix_neighbors,
        int parts_used,
    ) noexcept
    cdef void _build_key(
        self,
        bitset_t suffix_vertices,
        bitset_t* part_suffix_neighbors,
        int parts_used,
    ) noexcept
    cdef mp_limb_t* _find_slot(
        self,
        mp_limb_t* slots,
        size_t capacity,
        mp_limb_t hash,
        mp_limb_t* key,
    ) noexcept
    cdef bint _grow(self) noexcept
