from libc.string cimport memcmp, memcpy, memset
from cysignals.memory cimport sig_calloc, sig_free
from sage.libs.gmp.types cimport mp_limb_t


cdef enum:
    INITIAL_CAPACITY = 1024


cdef class SeenStates:
    """Set of states of the branch and bound, stored in an open addressing hash table with linear probing.

    A state is the number of parts used, the suffix and `sets_per_part` sets of
    vertices for each part, such as the suffix neighbors of the part, in an order
    that doesn't depend on the order of the parts. Each set of vertices takes
    `words` 64-bit words, and the state is stored as a key of `key_words` words,
    where the unused parts are zero. Each slot of the table is the hash of its key
    followed by the key. Hashes are never 0, so that 0 marks an empty slot.

    Once it has `max_size` states, no more are added.
    """

    def __cinit__(self, size_t words, int max_parts, size_t max_size, int sets_per_part=1):
        """`words` is the number of 64-bit words of the sets of vertices of the states."""
        if sizeof(mp_limb_t) != sizeof(uint64_t):
            raise ValueError('Bitset limbs must be 64 bits long')
        self.words = words
        self.max_parts = max_parts
        self.sets_per_part = sets_per_part
        self.key_words = 1 + words * (1 + sets_per_part * max_parts)
        self.max_size = max_size
        self.size = 0
        self.capacity = INITIAL_CAPACITY
        self.slots = <uint64_t*>sig_calloc(self.capacity * (1 + self.key_words), sizeof(uint64_t))
        self.key = <uint64_t*>sig_calloc(self.key_words, sizeof(uint64_t))
        self.part_key = <uint64_t*>sig_calloc(words * sets_per_part, sizeof(uint64_t))
        if self.slots == NULL or self.key == NULL or self.part_key == NULL:
            raise MemoryError

    def __dealloc__(self):
        sig_free(self.slots)
        sig_free(self.key)
        sig_free(self.part_key)

    cdef bint contains_or_add(
        self,
        bitset_t suffix_vertices,
        bitset_t* part_sets,
        int parts_used,
    ) noexcept:
        """Whether the state is in the set. If it isn't, it is added unless the set is full.

        `part_sets` has the `sets_per_part` sets of each part one after the other.
        The bitsets must have `words` limbs.
        """
        cdef size_t bitset_bytes = self.words * sizeof(uint64_t)
        cdef size_t part_words = self.words * self.sets_per_part
        cdef size_t part_bytes = part_words * sizeof(uint64_t)
        cdef uint64_t* parts_key = self.key + 1 + self.words
        cdef int part
        cdef int position
        cdef int i

        self.key[0] = parts_used
        memcpy(self.key + 1, suffix_vertices.bits, bitset_bytes)
        # Insertion sort of the parts by their bytes, so that their order doesn't matter.
        for part in range(parts_used):
            for i in range(self.sets_per_part):
                memcpy(
                    self.part_key + i * self.words,
                    part_sets[part * self.sets_per_part + i].bits,
                    bitset_bytes,
                )
            position = part
            while position > 0 and memcmp(
                parts_key + (position - 1) * part_words,
                self.part_key,
                part_bytes,
            ) > 0:
                memcpy(
                    parts_key + position * part_words,
                    parts_key + (position - 1) * part_words,
                    part_bytes,
                )
                position -= 1
            memcpy(parts_key + position * part_words, self.part_key, part_bytes)
        memset(parts_key + parts_used * part_words, 0, (self.max_parts - parts_used) * part_bytes)

        return self._contains_or_add_key()

    cdef bint contains_or_add_words(
        self,
        uint64_t suffix_vertices,
        uint64_t* part_suffix_neighbors,
        int parts_used,
    ) noexcept:
        """Same as `contains_or_add`, for sets of one word. `words` and `sets_per_part` must be 1."""
        cdef uint64_t* parts_key = self.key + 2
        cdef int part
        cdef int position

        self.key[0] = parts_used
        self.key[1] = suffix_vertices
        # Insertion sort of the parts, so that their order doesn't matter.
        for part in range(parts_used):
            position = part
            while position > 0 and parts_key[position - 1] > part_suffix_neighbors[part]:
                parts_key[position] = parts_key[position - 1]
                position -= 1
            parts_key[position] = part_suffix_neighbors[part]
        for part in range(parts_used, self.max_parts):
            parts_key[part] = 0

        return self._contains_or_add_key()

    cdef bint _contains_or_add_key(self) noexcept:
        cdef uint64_t hash = _hash_words(self.key, self.key_words)
        cdef uint64_t* slot = self._find_slot(self.slots, self.capacity, hash, self.key)
        if slot[0] != 0:
            return True
        if self.size >= self.max_size:
            return False
        if 2 * (self.size + 1) > self.capacity:
            if not self._grow():
                return False
            slot = self._find_slot(self.slots, self.capacity, hash, self.key)
        slot[0] = hash
        memcpy(slot + 1, self.key, self.key_words * sizeof(uint64_t))
        self.size += 1
        return False

    cdef uint64_t* _find_slot(
        self,
        uint64_t* slots,
        size_t capacity,
        uint64_t hash,
        uint64_t* key,
    ) noexcept:
        """The slot that holds `key`, or the empty slot where it goes."""
        cdef size_t slot_words = 1 + self.key_words
        cdef size_t i = hash & (capacity - 1)
        cdef uint64_t* slot
        while True:
            slot = slots + i * slot_words
            if slot[0] == 0 or (
                slot[0] == hash
                and memcmp(slot + 1, key, self.key_words * sizeof(uint64_t)) == 0
            ):
                return slot
            i = (i + 1) & (capacity - 1)

    cdef bint _grow(self) noexcept:
        """Double the capacity. Returns False if there is no memory for it."""
        cdef size_t slot_words = 1 + self.key_words
        cdef size_t new_capacity = 2 * self.capacity
        cdef uint64_t* new_slots = <uint64_t*>sig_calloc(new_capacity * slot_words, sizeof(uint64_t))
        if new_slots == NULL:
            return False
        cdef size_t i
        cdef uint64_t* slot
        for i in range(self.capacity):
            slot = self.slots + i * slot_words
            if slot[0] != 0:
                memcpy(
                    self._find_slot(new_slots, new_capacity, slot[0], slot + 1),
                    slot,
                    slot_words * sizeof(uint64_t),
                )
        sig_free(self.slots)
        self.slots = new_slots
        self.capacity = new_capacity
        return True


cdef inline uint64_t _hash_words(uint64_t* words, size_t count) noexcept:
    """Never 0."""
    cdef uint64_t hash = 0
    cdef size_t i
    for i in range(count):
        hash = (hash ^ words[i]) * 0x9E3779B97F4A7C15ULL
        hash ^= hash >> 32
    # Final mix of MurmurHash3, so that the low bits used for the slot index are well mixed.
    hash ^= hash >> 33
    hash *= 0xFF51AFD7ED558CCDULL
    hash ^= hash >> 33
    hash *= 0xC4CEB9FE1A85EC53ULL
    hash ^= hash >> 33
    return hash if hash != 0 else 1
