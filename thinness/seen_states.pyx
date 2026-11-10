from libc.string cimport memcmp, memcpy
from cysignals.memory cimport sig_calloc, sig_free, sig_malloc, sig_realloc
from sage.libs.gmp.types cimport mp_limb_t


cdef enum:
    INITIAL_CAPACITY = 1024


cdef class SeenStates:
    """Set of states of the branch and bound, stored in an open addressing hash table with linear probing.

    A state is the number of parts used, the suffix and `sets_per_part` sets of
    vertices for each part, such as the suffix neighbors of the part, in an order
    that doesn't depend on the order of the parts. Each set of vertices takes
    `words` 64-bit words, and the state is stored as a key with the number of
    parts used, the suffix and the sets of those parts, so it takes up to
    `key_words` words. The keys are stored one after the other in `keys`, and
    each slot of the table is the hash of its key followed by where the key
    starts in `keys`, so that the memory doesn't depend on the maximum number
    of parts. Hashes are never 0, so that 0 marks an empty slot.

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
        self.slots = <uint64_t*>sig_calloc(2 * self.capacity, sizeof(uint64_t))
        self.keys_used = 0
        self.keys_capacity = INITIAL_CAPACITY * self.key_words
        self.keys = <uint64_t*>sig_malloc(self.keys_capacity * sizeof(uint64_t))
        self.key = <uint64_t*>sig_calloc(self.key_words, sizeof(uint64_t))
        self.part_key = <uint64_t*>sig_calloc(words * sets_per_part, sizeof(uint64_t))
        if self.slots == NULL or self.keys == NULL or self.key == NULL or self.part_key == NULL:
            raise MemoryError

    def __dealloc__(self):
        sig_free(self.slots)
        sig_free(self.keys)
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

        return self._contains_or_add_key()

    cdef bint contains_or_add_words(
        self,
        uint64_t suffix_vertices,
        uint64_t* part_sets,
        int parts_used,
    ) noexcept:
        """Same as `contains_or_add`, for sets of one word. `words` must be 1."""
        cdef int sets_per_part = self.sets_per_part
        cdef uint64_t* parts_key = self.key + 2
        cdef uint64_t* sets
        cdef int part
        cdef int position
        cdef int i

        self.key[0] = parts_used
        self.key[1] = suffix_vertices
        # Insertion sort of the parts, so that their order doesn't matter.
        for part in range(parts_used):
            sets = part_sets + part * sets_per_part
            position = part
            while position > 0 and _compare_words(
                parts_key + (position - 1) * sets_per_part,
                sets,
                sets_per_part,
            ) > 0:
                for i in range(sets_per_part):
                    parts_key[position * sets_per_part + i] = parts_key[(position - 1) * sets_per_part + i]
                position -= 1
            for i in range(sets_per_part):
                parts_key[position * sets_per_part + i] = sets[i]

        return self._contains_or_add_key()

    cdef bint _contains_or_add_key(self) noexcept:
        cdef size_t key_words = self._used_key_words(self.key)
        cdef uint64_t hash = _hash_words(self.key, key_words)
        cdef uint64_t* slot = self._find_slot(hash, self.key, key_words)
        if slot[0] != 0:
            return True
        if self.size >= self.max_size:
            return False
        if self.keys_used + key_words > self.keys_capacity and not self._grow_keys():
            return False
        if 2 * (self.size + 1) > self.capacity:
            if not self._grow():
                return False
            slot = self._find_slot(hash, self.key, key_words)
        slot[0] = hash
        slot[1] = self.keys_used
        memcpy(self.keys + self.keys_used, self.key, key_words * sizeof(uint64_t))
        self.keys_used += key_words
        self.size += 1
        return False

    cdef uint64_t* _find_slot(self, uint64_t hash, uint64_t* key, size_t key_words) noexcept:
        """The slot that holds `key`, of `key_words` words, or the empty slot where it goes."""
        cdef size_t i = hash & (self.capacity - 1)
        cdef uint64_t* slot
        cdef uint64_t* stored_key
        while True:
            slot = self.slots + 2 * i
            if slot[0] == 0:
                return slot
            if slot[0] == hash:
                stored_key = self.keys + slot[1]
                # Keys with different numbers of parts have different lengths, so
                # their first words are compared before the rest.
                if stored_key[0] == key[0] and memcmp(stored_key, key, key_words * sizeof(uint64_t)) == 0:
                    return slot
            i = (i + 1) & (self.capacity - 1)

    cdef size_t _used_key_words(self, uint64_t* key) noexcept:
        """The words of `key` that hold the number of parts used, the suffix and the sets of those parts."""
        return 1 + self.words * (1 + self.sets_per_part * key[0])

    cdef bint _grow(self) noexcept:
        """Double the capacity. Returns False if there is no memory for it."""
        cdef size_t new_capacity = 2 * self.capacity
        cdef uint64_t* new_slots = <uint64_t*>sig_calloc(2 * new_capacity, sizeof(uint64_t))
        if new_slots == NULL:
            return False
        cdef size_t i
        cdef size_t j
        cdef uint64_t* slot
        for i in range(self.capacity):
            slot = self.slots + 2 * i
            if slot[0] != 0:
                # The keys are all different, so each one goes to the first empty slot.
                j = slot[0] & (new_capacity - 1)
                while new_slots[2 * j] != 0:
                    j = (j + 1) & (new_capacity - 1)
                new_slots[2 * j] = slot[0]
                new_slots[2 * j + 1] = slot[1]
        sig_free(self.slots)
        self.slots = new_slots
        self.capacity = new_capacity
        return True

    cdef bint _grow_keys(self) noexcept:
        """Double the space for keys. Returns False if there is no memory for it."""
        cdef size_t new_capacity = 2 * self.keys_capacity
        cdef uint64_t* new_keys = <uint64_t*>sig_realloc(self.keys, new_capacity * sizeof(uint64_t))
        if new_keys == NULL:
            return False
        self.keys = new_keys
        self.keys_capacity = new_capacity
        return True


cdef inline int _compare_words(uint64_t* first, uint64_t* second, int count) noexcept:
    """Compares the first `count` words of `first` and `second` lexicographically."""
    cdef int i
    for i in range(count):
        if first[i] != second[i]:
            return 1 if first[i] > second[i] else -1
    return 0


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
