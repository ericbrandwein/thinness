from libc.stdint cimport uint64_t
from libc.string cimport memcmp, memcpy, memset
from cysignals.memory cimport sig_calloc, sig_free


cdef enum:
    INITIAL_CAPACITY = 1024


cdef class SeenStates:
    """Set of states of the branch and bound, stored in an open addressing hash table with linear probing.

    A state is the number of parts used, the suffix and the suffix neighbors of
    each part, in an order that doesn't depend on the order of the parts. It is
    stored as a key of `key_limbs` limbs, where the unused parts are zero. Each
    slot of the table is the hash of its key followed by the key. Hashes are
    never 0, so that 0 marks an empty slot.

    Once it has `max_size` states, no more are added.
    """

    def __cinit__(self, size_t limbs, int max_parts, size_t max_size):
        """`limbs` is the number of limbs of the bitsets of the states."""
        self.limbs = limbs
        self.max_parts = max_parts
        self.key_limbs = 1 + limbs * (1 + max_parts)
        self.max_size = max_size
        self.size = 0
        self.capacity = INITIAL_CAPACITY
        self.slots = <mp_limb_t*>sig_calloc(self.capacity * (1 + self.key_limbs), sizeof(mp_limb_t))
        self.key = <mp_limb_t*>sig_calloc(self.key_limbs, sizeof(mp_limb_t))
        if self.slots == NULL or self.key == NULL:
            raise MemoryError

    def __dealloc__(self):
        sig_free(self.slots)
        sig_free(self.key)

    cdef bint contains_or_add(
        self,
        bitset_t suffix_vertices,
        bitset_t* part_suffix_neighbors,
        int parts_used,
    ) noexcept:
        """Whether the state is in the set. If it isn't, it is added unless the set is full."""
        self._build_key(suffix_vertices, part_suffix_neighbors, parts_used)
        cdef mp_limb_t hash = _hash_limbs(self.key, self.key_limbs)
        cdef mp_limb_t* slot = self._find_slot(self.slots, self.capacity, hash, self.key)
        if slot[0] != 0:
            return True
        if self.size >= self.max_size:
            return False
        if 2 * (self.size + 1) > self.capacity:
            if not self._grow():
                return False
            slot = self._find_slot(self.slots, self.capacity, hash, self.key)
        slot[0] = hash
        memcpy(slot + 1, self.key, self.key_limbs * sizeof(mp_limb_t))
        self.size += 1
        return False

    cdef void _build_key(
        self,
        bitset_t suffix_vertices,
        bitset_t* part_suffix_neighbors,
        int parts_used,
    ) noexcept:
        cdef size_t bitset_bytes = self.limbs * sizeof(mp_limb_t)
        cdef mp_limb_t* parts_key = self.key + 1 + self.limbs
        cdef int part
        cdef int position

        self.key[0] = parts_used
        memcpy(self.key + 1, suffix_vertices.bits, bitset_bytes)
        # Insertion sort of the parts by their bytes, so that their order doesn't matter.
        for part in range(parts_used):
            position = part
            while position > 0 and memcmp(
                parts_key + (position - 1) * self.limbs,
                part_suffix_neighbors[part].bits,
                bitset_bytes,
            ) > 0:
                memcpy(
                    parts_key + position * self.limbs,
                    parts_key + (position - 1) * self.limbs,
                    bitset_bytes,
                )
                position -= 1
            memcpy(parts_key + position * self.limbs, part_suffix_neighbors[part].bits, bitset_bytes)
        memset(parts_key + parts_used * self.limbs, 0, (self.max_parts - parts_used) * bitset_bytes)

    cdef mp_limb_t* _find_slot(
        self,
        mp_limb_t* slots,
        size_t capacity,
        mp_limb_t hash,
        mp_limb_t* key,
    ) noexcept:
        """The slot that holds `key`, or the empty slot where it goes."""
        cdef size_t slot_limbs = 1 + self.key_limbs
        cdef size_t i = hash & (capacity - 1)
        cdef mp_limb_t* slot
        while True:
            slot = slots + i * slot_limbs
            if slot[0] == 0 or (
                slot[0] == hash
                and memcmp(slot + 1, key, self.key_limbs * sizeof(mp_limb_t)) == 0
            ):
                return slot
            i = (i + 1) & (capacity - 1)

    cdef bint _grow(self) noexcept:
        """Double the capacity. Returns False if there is no memory for it."""
        cdef size_t slot_limbs = 1 + self.key_limbs
        cdef size_t new_capacity = 2 * self.capacity
        cdef mp_limb_t* new_slots = <mp_limb_t*>sig_calloc(new_capacity * slot_limbs, sizeof(mp_limb_t))
        if new_slots == NULL:
            return False
        cdef size_t i
        cdef mp_limb_t* slot
        for i in range(self.capacity):
            slot = self.slots + i * slot_limbs
            if slot[0] != 0:
                memcpy(
                    self._find_slot(new_slots, new_capacity, slot[0], slot + 1),
                    slot,
                    slot_limbs * sizeof(mp_limb_t),
                )
        sig_free(self.slots)
        self.slots = new_slots
        self.capacity = new_capacity
        return True


cdef inline mp_limb_t _hash_limbs(mp_limb_t* limbs, size_t count) noexcept:
    """Never 0."""
    cdef uint64_t hash = 0
    cdef size_t i
    for i in range(count):
        hash = (hash ^ <uint64_t>limbs[i]) * 0x9E3779B97F4A7C15ULL
        hash ^= hash >> 32
    # Final mix of MurmurHash3, so that the low bits used for the slot index are well mixed.
    hash ^= hash >> 33
    hash *= 0xFF51AFD7ED558CCDULL
    hash ^= hash >> 33
    hash *= 0xC4CEB9FE1A85EC53ULL
    hash ^= hash >> 33
    cdef mp_limb_t result = <mp_limb_t>hash
    return result if result != 0 else 1
