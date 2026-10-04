/* Stage 2 host oracle: IDA* + one nibble-packed pattern database (PDB).
 * Reuses the baseline's cube model (source/twist tables, 9 moves).
 * Build: gcc -O2 -o stage2 stage2.c
 * Run:   ./stage2 PPPPPPPOOOOOOO   solve one state
 *        ./stage2 --verify         gates H1, H3 + node statistics
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    CUBIES = 7,
    PERMS = 5040,
    ORIENTS = 729,
    STATES = PERMS * ORIENTS,
    MOVES = 9,
    PDB_LOC = 210, /* 7 * 6 * 5 locations of cubies 0, 1, 2 */
    PDB_N = ORIENTS * PDB_LOC
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};
static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6}, {0, 1, 2, 4, 5, 6, 3}, {0, 2, 5, 3, 1, 4, 6}};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0}, {0, 0, 0, 1, 2, 1, 2}, {0, 0, 0, 0, 0, 0, 0}};

static state_t quarter_turn(state_t s, uint8_t f)
{
    state_t r;
    for (int i = 0; i < CUBIES; ++i) {
        r.p[i] = s.p[source[f][i]];
        r.o[i] = (uint8_t) ((s.o[source[f][i]] + twist[f][i]) % 3);
    }
    return r;
}

static state_t apply_move(state_t s, uint8_t m)
{
    for (int i = 0; i < m % 3 + 1; ++i)
        s = quarter_turn(s, (uint8_t) (m / 3));
    return s;
}

static uint32_t rank_perm(const uint8_t *p)
{
    uint32_t r = 0;
    for (int i = 0; i < CUBIES; ++i) {
        int sm = 0;
        for (int j = i + 1; j < CUBIES; ++j)
            sm += p[j] < p[i];
        r = r * (CUBIES - i) + sm;
    }
    return r;
}

static uint32_t rank_orient(const uint8_t *o)
{
    uint32_t r = 0;
    for (int i = 0; i < 6; ++i)
        r = r * 3 + o[i];
    return r;
}

static uint32_t rank_state(const state_t *s)
{
    return rank_perm(s->p) * ORIENTS + rank_orient(s->o);
}

static void unrank_state(uint32_t rank, state_t *s)
{
    uint8_t av[CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    uint32_t p = rank / ORIENTS, o = rank % ORIENTS, f = 720;
    int sum = 0;
    for (int i = 0; i < CUBIES; ++i) {
        int q = (int) (p / f);
        p %= f;
        s->p[i] = av[q];
        for (int j = q; j + 1 < CUBIES - i; ++j)
            av[j] = av[j + 1];
        if (i < 5)
            f /= 6 - i;
    }
    for (int i = 5; i >= 0; --i) {
        s->o[i] = o % 3;
        sum += s->o[i];
        o /= 3;
    }
    s->o[6] = (3 - sum % 3) % 3;
}

/* PDB abstraction: orientation of every slot + location of cubies 0, 1, 2.
 * Orientation updates depend only on the slot, so this is a true quotient of
 * the Cayley graph and its BFS distance never exceeds the real distance. */
static uint32_t pdb_index(const uint8_t *o, const uint8_t *loc)
{
    uint32_t r1 = loc[1] - (loc[1] > loc[0]);
    uint32_t r2 = loc[2] - (loc[2] > loc[0]) - (loc[2] > loc[1]);
    return rank_orient(o) * PDB_LOC + (loc[0] * 6 + r1) * 5 + r2;
}

static void state_loc(const state_t *s, uint8_t *loc)
{
    for (int j = 0; j < CUBIES; ++j)
        if (s->p[j] < 3)
            loc[s->p[j]] = (uint8_t) j;
}

static uint8_t *pdb;           /* two 4-bit entries per byte */
static uint8_t perm_h[PERMS];  /* byte here; 4-bit when packed on target */
static int pdb_max, perm_max;

static unsigned nib_get(const uint8_t *t, uint32_t i)
{
    return (t[i >> 1] >> ((i & 1) * 4)) & 15;
}

static void nib_set(uint8_t *t, uint32_t i, unsigned v)
{
    t[i >> 1] = (uint8_t) ((t[i >> 1] & ~(15 << ((i & 1) * 4))) |
                           (v << ((i & 1) * 4)));
}

static state_t pdb_decode(uint32_t idx)
{
    state_t s;
    uint32_t oi = idx / PDB_LOC, l = idx % PDB_LOC;
    int sum = 0;
    for (int i = 5; i >= 0; --i) {
        s.o[i] = oi % 3;
        sum += s.o[i];
        oi /= 3;
    }
    s.o[6] = (3 - sum % 3) % 3;
    uint8_t l0 = l / 30, r1 = (l / 5) % 6, r2 = l % 5;
    uint8_t l1 = r1 + (r1 >= l0);
    uint8_t a = l0 < l1 ? l0 : l1, b = l0 < l1 ? l1 : l0;
    uint8_t l2 = r2 + (r2 >= a);
    l2 += l2 >= b;
    for (int j = 0; j < CUBIES; ++j)
        s.p[j] = 7;
    s.p[l0] = 0;
    s.p[l1] = 1;
    s.p[l2] = 2;
    for (int j = 0, k = 3; j < CUBIES; ++j)
        if (s.p[j] == 7)
            s.p[j] = (uint8_t) k++;
    return s;
}

static void build_pdb(void)
{
    uint8_t *dist = malloc(PDB_N);
    uint32_t *q = malloc(PDB_N * 4);
    memset(dist, 255, PDB_N);
    pdb = calloc(PDB_N / 2, 1);
    state_t id = {{0, 1, 2, 3, 4, 5, 6}, {0}};
    uint8_t loc[3];
    state_loc(&id, loc);
    uint32_t h = 0, t = 1;
    q[0] = pdb_index(id.o, loc);
    dist[q[0]] = 0;
    while (h < t) {
        uint32_t cur = q[h++];
        state_t s = pdb_decode(cur);
        for (int f = 0; f < 3; ++f) {
            state_t n = s;
            for (int tn = 0; tn < 3; ++tn) {
                n = quarter_turn(n, (uint8_t) f);
                state_loc(&n, loc);
                uint32_t ni = pdb_index(n.o, loc);
                if (dist[ni] == 255) {
                    dist[ni] = dist[cur] + 1;
                    q[t++] = ni;
                }
            }
        }
    }
    if (t != PDB_N) {
        fputs("PDB not fully reachable\n", stderr);
        exit(1);
    }
    for (uint32_t i = 0; i < PDB_N; ++i) {
        nib_set(pdb, i, dist[i]);
        if (dist[i] > pdb_max)
            pdb_max = dist[i];
    }
    free(dist);
    free(q);
}

static void build_perm_h(void)
{
    static uint32_t q[PERMS];
    uint32_t h = 0, t = 1;
    memset(perm_h, 255, PERMS);
    q[0] = 0;
    perm_h[0] = 0;
    while (h < t) {
        state_t s;
        unrank_state(q[h++] * ORIENTS, &s);
        uint8_t d = perm_h[rank_perm(s.p)];
        for (int f = 0; f < 3; ++f) {
            state_t n = s;
            for (int tn = 0; tn < 3; ++tn) {
                n = quarter_turn(n, (uint8_t) f);
                uint32_t r = rank_perm(n.p);
                if (perm_h[r] == 255) {
                    perm_h[r] = d + 1;
                    q[t++] = r;
                    if (d + 1 > perm_max)
                        perm_max = d + 1;
                }
            }
        }
    }
}

static int heur(const state_t *s)
{
    uint8_t loc[3];
    state_loc(s, loc);
    int a = (int) nib_get(pdb, pdb_index(s->o, loc));
    int b = perm_h[rank_perm(s->p)];
    return a > b ? a : b;
}

/* IDA*: never turn the same face twice in a row, so 6 of 9 moves remain. */
static uint64_t nodes;
static uint8_t path[32];

static int ida_dfs(state_t s, int g, int bound, int last_face)
{
    ++nodes;
    int h = heur(&s);
    if (g + h > bound)
        return 0;
    if (h == 0 && rank_state(&s) == 0)
        return 1;
    for (int m = 0; m < MOVES; ++m) {
        if (m / 3 == last_face)
            continue;
        path[g] = (uint8_t) m;
        if (ida_dfs(apply_move(s, (uint8_t) m), g + 1, bound, m / 3))
            return 1;
    }
    return 0;
}

static int solve(state_t s)
{
    nodes = 0;
    for (int b = heur(&s);; ++b)
        if (ida_dfs(s, 0, b, -1))
            return b;
}

int main(int argc, char **argv)
{
    build_pdb();
    build_perm_h();
    printf("PDB: %u entries, 4-bit => %u bytes, max depth %d; "
           "perm table %d entries, max %d\n",
           PDB_N, PDB_N / 2, pdb_max, PERMS, perm_max);
    if (argc == 2 && strcmp(argv[1], "--verify")) {
        state_t s;
        const char *a = argv[1];
        if (strlen(a) != 14)
            return 2;
        for (int i = 0; i < 7; ++i) {
            s.p[i] = a[i] - '1';
            s.o[i] = a[i + 7] - '1';
        }
        int d = solve(s);
        for (int i = 0; i < d; ++i)
            printf("%s%s", i ? " " : "", move_names[path[i]]);
        printf("\n(%d moves, %llu nodes)\n", d, (unsigned long long) nodes);
        return 0;
    }

    /* ground truth: full BFS over all 3,674,160 states */
    uint8_t *dist = malloc(STATES);
    uint32_t *q = malloc((size_t) STATES * 4);
    memset(dist, 255, STATES);
    dist[0] = 0;
    q[0] = 0;
    uint32_t h = 0, t = 1;
    while (h < t) {
        state_t s;
        uint32_t c = q[h++];
        unrank_state(c, &s);
        for (int f = 0; f < 3; ++f) {
            state_t n = s;
            for (int tn = 0; tn < 3; ++tn) {
                n = quarter_turn(n, (uint8_t) f);
                uint32_t r = rank_state(&n);
                if (dist[r] == 255) {
                    dist[r] = dist[c] + 1;
                    q[t++] = r;
                }
            }
        }
    }

    /* H1: admissibility over every state */
    long viol = 0, hist[12] = {0}, slack = 0;
    for (uint32_t r = 0; r < STATES; ++r) {
        state_t s;
        unrank_state(r, &s);
        int hv = heur(&s);
        viol += hv > dist[r];
        slack += dist[r] - hv;
        hist[dist[r]]++;
    }
    printf("H1 violations: %ld; mean(h* - h) = %.3f\n", viol,
           (double) slack / STATES);

    /* H3: optimality on every distance-11 state + ~1/180 of the rest */
    uint64_t seed = 12345, tot = 0, mx = 0, tot11 = 0, mx11 = 0;
    long bad = 0, n = 0, n11 = 0;
    for (uint32_t r = 0; r < STATES; ++r) {
        int is11 = dist[r] == 11;
        if (!is11) {
            seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
            if ((seed >> 33) % 180)
                continue;
        }
        state_t s;
        unrank_state(r, &s);
        int d = solve(s);
        state_t c = s;
        for (int i = 0; i < d; ++i)
            c = apply_move(c, path[i]);
        bad += d != dist[r] || rank_state(&c) != 0;
        ++n;
        tot += nodes;
        mx = nodes > mx ? nodes : mx;
        if (is11) {
            ++n11;
            tot11 += nodes;
            mx11 = nodes > mx11 ? nodes : mx11;
        }
    }
    printf("H3 checked %ld states, wrong = %ld; nodes mean %.0f max %llu\n", n,
           bad, (double) tot / n, (unsigned long long) mx);
    printf("distance-11: %ld states, nodes mean %.0f max %llu\n", n11,
           n11 ? (double) tot11 / n11 : 0.0, (unsigned long long) mx11);
    for (int i = 0; i < 12; ++i)
        printf("d=%d: %ld\n", i, hist[i]);
    return 0;
}
