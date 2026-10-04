/* Stage 3: the Stage 2 algorithm (IDA* + 4-bit PDB), rewritten so that the
 * search loop only uses what RV32I gives for free:
 *   - no recursion (explicit stack of at most 12 frames),
 *   - no multiply/divide/modulo in the search (shift+add, table lookups),
 *   - no permutation ranking per node: the search state is just the pair
 *     (orientation index, location index), advanced by two table loads,
 *   - no state_t copies; the 7-byte state is only rebuilt when the PDB says 0.
 * Build: gcc -O2 -Wall -o stage3 stage3.c
 * Run:   ./stage3 PPPPPPPOOOOOOO | ./stage3 --test | ./stage3 --verify
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


#ifdef _WIN32
#include <windows.h>
static double now_ns(void)
{
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double) c.QuadPart * 1e9 / (double) f.QuadPart;
}
#else
#include <time.h>
static double now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1e9 + t.tv_nsec;
}
#endif

enum { CUBIES = 7, PERMS = 5040, ORIENTS = 729, STATES = PERMS * ORIENTS,
       MOVES = 9, LOCS = 210, PDB_N = ORIENTS * LOCS, MAXD = 12 };

typedef struct { uint8_t p[CUBIES], o[CUBIES]; } state_t;

static const char *const move_names[MOVES] = {"R", "R2", "R'", "B", "B2",
                                              "B'", "D", "D2", "D'"};
static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6}, {0, 1, 2, 4, 5, 6, 3}, {0, 2, 5, 3, 1, 4, 6}};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0}, {0, 0, 0, 1, 2, 1, 2}, {0, 0, 0, 0, 0, 0, 0}};

/* ---------------- host-only helpers (table generation, checking) -------- */
static state_t quarter_turn(state_t s, int f)
{
    state_t r;
    for (int i = 0; i < CUBIES; ++i) {
        r.p[i] = s.p[source[f][i]];
        r.o[i] = (uint8_t) ((s.o[source[f][i]] + twist[f][i]) % 3);
    }
    return r;
}
static state_t apply_move(state_t s, int m)
{
    for (int i = 0; i < m % 3 + 1; ++i)
        s = quarter_turn(s, m / 3);
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

/* Location index of cubies 0,1,2 in [0,210): (l0*6 + r1)*5 + r2. */
static uint32_t loc_index(const uint8_t *loc)
{
    uint32_t r1 = loc[1] - (loc[1] > loc[0]);
    uint32_t r2 = loc[2] - (loc[2] > loc[0]) - (loc[2] > loc[1]);
    return (loc[0] * 6 + r1) * 5 + r2;
}
static void state_loc(const state_t *s, uint8_t *loc)
{
    for (int j = 0; j < CUBIES; ++j)
        if (s->p[j] < 3)
            loc[s->p[j]] = (uint8_t) j;
}
static state_t decode_abstract(uint32_t oi, uint32_t l)
{
    state_t s;
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

/* ---------------- the data that would live in .rodata on the target ----- */
/* Rows are padded to 1024 / 256 so that a row is addressed by a shift.     */
static uint16_t onext[3][1024]; /* orientation index after one quarter turn */
static uint8_t lnext[3][256];   /* location index after one quarter turn    */
static uint8_t pdb[PDB_N / 2];  /* 4-bit distance, two entries per byte     */
static uint8_t pdb_ref[PDB_N];  /* host-only unpacked reference for H2/H4   */

static void build_tables(void)
{
    uint8_t *dist = pdb_ref;
    static uint32_t q[PDB_N];
    uint32_t h = 0, t = 1;
    for (uint32_t oi = 0; oi < ORIENTS; ++oi) {
        state_t s = decode_abstract(oi, 0);
        for (int f = 0; f < 3; ++f)
            onext[f][oi] = (uint16_t) rank_orient(quarter_turn(s, f).o);
    }
    for (uint32_t l = 0; l < LOCS; ++l) {
        state_t s = decode_abstract(0, l);
        for (int f = 0; f < 3; ++f) {
            uint8_t loc[3];
            state_t n = quarter_turn(s, f);
            state_loc(&n, loc);
            lnext[f][l] = (uint8_t) loc_index(loc);
        }
    }
    /* BFS over the abstract graph using only the two small tables. */
    memset(dist, 255, PDB_N);
    dist[0] = 0;
    q[0] = 0;
    while (h < t) {
        uint32_t cur = q[h++], oi = cur / LOCS, l = cur % LOCS;
        for (int f = 0; f < 3; ++f) {
            uint32_t no = oi, nl = l;
            for (int tn = 0; tn < 3; ++tn) {
                no = onext[f][no];
                nl = lnext[f][nl];
                uint32_t ni = no * LOCS + nl;
                if (dist[ni] == 255) {
                    dist[ni] = dist[cur] + 1;
                    q[t++] = ni;
                }
            }
        }
    }
    if (t != PDB_N)
        exit(3);
    for (uint32_t i = 0; i < PDB_N; ++i)
        pdb[i >> 1] = (uint8_t) (pdb[i >> 1] | dist[i] << ((i & 1) * 4));
}

/* ---------------- the search: RV32I-friendly ---------------------------- */
static uint64_t nodes;
static long bad_total;

/* o*210 + l without a multiplier: 210 = 128 + 64 + 16 + 2. */
static inline uint32_t pdb_idx(uint32_t o, uint32_t l)
{
    return (o << 7) + (o << 6) + (o << 4) + (o << 1) + l;
}
/* branch-free nibble read: shift by 0 or 4 chosen from bit 0 of the index. */
static inline uint32_t pdb_get(uint32_t i)
{
    return (pdb[i >> 1] >> ((i & 1) << 2)) & 15;
}

static int is_solved_after(const state_t *root, const uint8_t *path, int n)
{
    state_t s = *root;
    for (int i = 0; i < n; ++i)
        s = apply_move(s, path[i]);
    for (int i = 0; i < CUBIES; ++i)
        if (s.p[i] != i || s.o[i])
            return 0;
    return 1;
}

static uint8_t path[MAXD];

static int search(const state_t *root)
{
    uint8_t loc[3];
    state_loc(root, loc);
    uint32_t o0 = rank_orient(root->o), l0 = loc_index(loc);
    int h0 = (int) pdb_get(pdb_idx(o0, l0));
    nodes = 1;
    if (h0 == 0 && is_solved_after(root, path, 0))
        return 0;
    for (int bound = h0;; ++bound) {
        /* frame d = a node at depth d plus a cursor over its children */
        uint16_t no[MAXD + 1], co[MAXD + 1];   /* node / cumulative orient */
        uint8_t nl[MAXD + 1], cl[MAXD + 1];    /* node / cumulative loc    */
        uint8_t face[MAXD + 1], turn[MAXD + 1], last[MAXD + 1];
        int d = 0;
        no[0] = co[0] = (uint16_t) o0;
        nl[0] = cl[0] = (uint8_t) l0;
        face[0] = turn[0] = 0;
        last[0] = 4;
        for (;;) {
            if (turn[d] == 3) {            /* finished one face: next face */
                turn[d] = 0;
                ++face[d];
                co[d] = no[d];
                cl[d] = nl[d];
            }
            if (face[d] == 3) {            /* frame exhausted: backtrack   */
                if (d == 0)
                    break;
                --d;
                continue;
            }
            if (face[d] == last[d]) {      /* never repeat the same face   */
                ++face[d];
                continue;
            }
            uint32_t f = face[d];
            co[d] = onext[f][co[d]];       /* one more quarter turn        */
            cl[d] = lnext[f][cl[d]];
            path[d] = (uint8_t) ((f << 1) + f + turn[d]);
            ++turn[d];
            ++nodes;
            int h = (int) pdb_get(pdb_idx(co[d], cl[d]));
            if (d + 1 + h > bound)
                continue;
            if (h == 0 && is_solved_after(root, path, d + 1))
                return d + 1;
            if (d + 1 == bound)            /* no budget left for children  */
                continue;
            no[d + 1] = co[d];
            nl[d + 1] = cl[d];
            co[d + 1] = co[d];
            cl[d + 1] = cl[d];
            face[d + 1] = turn[d + 1] = 0;
            last[d + 1] = (uint8_t) f;
            ++d;
        }
    }
}

/* ---------------- driver ------------------------------------------------ */
static int parse(const char *a, state_t *s)
{
    if (strlen(a) != 14)
        return 0;
    for (int i = 0; i < 7; ++i) {
        s->p[i] = (uint8_t) (a[i] - '1');
        s->o[i] = (uint8_t) (a[i + 7] - '1');
        if (s->p[i] > 6 || s->o[i] > 2)
            return 0;
    }
    return 1;
}
static void print_path(int d)
{
    for (int i = 0; i < d; ++i)
        printf("%s%s", i ? " " : "", move_names[path[i]]);
}

int main(int argc, char **argv)
{
    int bench = argc == 2 && !strcmp(argv[1], "--bench");
    build_tables();
    printf("tables: pdb %zu B, onext %zu B, lnext %zu B => %zu B\n",
           sizeof pdb, sizeof onext, sizeof lnext,
           sizeof pdb + sizeof onext + sizeof lnext);
    if (argc == 2 && !strcmp(argv[1], "--test")) {
        static const struct { const char *name, *state; int dist; } cases[] = {
            {"solved cube", "12345671111111", 0},
            {"short scramble (R B' D)", "23475162132323", 3},
            {"distance-11 state", "21345671111111", 11},
        };
        int fail = 0;
        for (unsigned k = 0; k < sizeof cases / sizeof *cases; ++k) {
            state_t s;
            parse(cases[k].state, &s);
            int d = search(&s);
            int ok = d == cases[k].dist && is_solved_after(&s, path, d);
            fail += !ok;
            printf("[%s] %-26s %s: ", ok ? "PASS" : "FAIL", cases[k].name, cases[k].state);
            print_path(d);
            printf("%s(%d moves, %llu nodes)\n", d ? " " : "", d, (unsigned long long) nodes);
        }
        return fail != 0;
    }
    int full = argc == 2 && !strcmp(argv[1], "--full");
    int hcheck = argc == 2 && !strcmp(argv[1], "--hcheck");
    if (argc == 2 && strcmp(argv[1], "--verify") && strcmp(argv[1], "--bench") &&
        !full && !hcheck) {
        state_t s;
        if (!parse(argv[1], &s))
            return 2;
        int d = search(&s);
        print_path(d);
        printf("\n(%d moves, %llu nodes)\n", d, (unsigned long long) nodes);
        return 0;
    }
    /* --verify: BFS ground truth, then optimality of every distance-11 state
     * plus a 1/180 sample of the rest, and node statistics. */
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
                n = quarter_turn(n, f);
                uint32_t r = rank_state(&n);
                if (dist[r] == 255) {
                    dist[r] = dist[c] + 1;
                    q[t++] = r;
                }
            }
        }
    }

    if (hcheck) {
        /* H1: the packed heuristic never exceeds the exact distance. */
        long viol = 0, tight = 0;
        for (uint32_t r = 0; r < STATES; ++r) {
            state_t s;
            unrank_state(r, &s);
            uint8_t loc[3];
            state_loc(&s, loc);
            int hv = (int) pdb_get(pdb_idx(rank_orient(s.o), loc_index(loc)));
            viol += hv > dist[r];
            tight += hv == dist[r];
        }
        printf("H1: %d states checked, violations = %ld (h == d on %ld)\n",
               STATES, viol, tight);

        /* H2: every table is fully populated; maximum and solved entry. */
        long fail2 = 0, unset = 0;
        long hist[16] = {0};
        for (uint32_t i = 0; i < PDB_N; ++i) {
            unset += pdb_ref[i] == 255;
            if (pdb_ref[i] < 16)
                hist[pdb_ref[i]]++;
        }
        int pmax = 0;
        for (int v = 0; v < 16; ++v)
            if (hist[v])
                pmax = v;
        fail2 += unset != 0 || hist[0] != 1 || pdb_ref[0] != 0;
        printf("H2 pdb: %d entries, unset = %ld, zero entries = %ld (index 0 = %d),"
               " max = %d\n", PDB_N, unset, hist[0], pdb_ref[0], pmax);
        for (int v = 0; v <= pmax; ++v)
            printf("    value %2d: %6ld entries\n", v, hist[v]);
        for (int f = 0; f < 3; ++f) {
            static uint8_t seen[1024];
            long badrow = 0;
            memset(seen, 0, sizeof seen);
            for (int i = 0; i < ORIENTS; ++i)
                badrow += onext[f][i] >= ORIENTS || seen[onext[f][i]]++;
            for (int i = ORIENTS; i < 1024; ++i)
                badrow += onext[f][i] != 0;
            memset(seen, 0, sizeof seen);
            for (int i = 0; i < LOCS; ++i)
                badrow += lnext[f][i] >= LOCS || seen[lnext[f][i]]++;
            for (int i = LOCS; i < 256; ++i)
                badrow += lnext[f][i] != 0;
            printf("H2 face %d: onext/lnext rows are permutations with zero"
                   " padding, bad = %ld\n", f, badrow);
            fail2 += badrow;
        }
        /* the tables agree with the full 7-cubie model on every real state */
        long mism = 0;
        for (uint32_t r = 0; r < STATES; ++r) {
            state_t s;
            unrank_state(r, &s);
            uint8_t loc[3];
            state_loc(&s, loc);
            uint32_t o = rank_orient(s.o), l = loc_index(loc);
            for (int f = 0; f < 3; ++f) {
                state_t n = quarter_turn(s, f);
                uint8_t nloc[3];
                state_loc(&n, nloc);
                mism += onext[f][o] != rank_orient(n.o) ||
                        lnext[f][l] != loc_index(nloc);
            }
        }
        printf("H2 transitions vs full model: %d states x 3 faces, mismatches = %ld\n",
               STATES, mism);
        fail2 += mism;
        printf("H2: %s\n", fail2 ? "FAIL" : "PASS");

        /* H4: packed accessor equals the unpacked reference at even and odd i. */
        long even_bad = 0, odd_bad = 0;
        for (uint32_t i = 0; i < PDB_N; ++i) {
            int diff = (int) pdb_get(i) != pdb_ref[i];
            if (i & 1)
                odd_bad += diff;
            else
                even_bad += diff;
        }
        printf("H4: %d even + %d odd indices, mismatches even = %ld odd = %ld,"
               " first %d/%d, last %d/%d\n", PDB_N / 2, PDB_N / 2, even_bad,
               odd_bad, (int) pdb_get(0), pdb_ref[0], (int) pdb_get(PDB_N - 1),
               pdb_ref[PDB_N - 1]);
        printf("H4: %s\n", even_bad || odd_bad ? "FAIL" : "PASS");
        return viol || fail2 || even_bad || odd_bad;
    }

    if (full) {
        /* H3, exhaustive: every one of the STATES states must return a path
         * of exactly the BFS length that also reaches the solved cube. */
        long cnt[12] = {0}, wrong[12] = {0};
        uint64_t tot[12] = {0}, mx[12] = {0};
        double t0 = now_ns();
        for (uint32_t r = 0; r < STATES; ++r) {
            state_t s;
            unrank_state(r, &s);
            int d = dist[r];
            int len = search(&s);
            cnt[d]++;
            wrong[d] += len != d || !is_solved_after(&s, path, len);
            tot[d] += nodes;
            mx[d] = nodes > mx[d] ? nodes : mx[d];
        }
        double secs = (now_ns() - t0) / 1e9;
        long bad = 0, n = 0;
        printf("%-3s %9s %6s %12s %10s\n", "d", "states", "wrong", "mean nodes",
               "max nodes");
        for (int d = 0; d <= 11; ++d) {
            printf("%-3d %9ld %6ld %12.0f %10llu\n", d, cnt[d], wrong[d],
                   cnt[d] ? (double) tot[d] / cnt[d] : 0.0,
                   (unsigned long long) mx[d]);
            bad += wrong[d];
            n += cnt[d];
        }
        printf("H3 exhaustive: checked %ld states, wrong = %ld, wall %.1f s\n", n,
               bad, secs);
        return bad != 0;
    }

    if (bench) {
        /* same sample in both programs: all distance-11 states, and about
         * 3000 random states from each of the distance 7..10 layers */
        long cnt[12] = {0};
        for (uint32_t r = 0; r < STATES; ++r)
            cnt[dist[r]]++;
        uint64_t seed = 777;
        printf("%-3s %8s %12s %10s %14s %10s %9s\n", "d", "states",
               "mean nodes", "max nodes", "total nodes", "time ms", "ns/node");
        for (int d = 7; d <= 11; ++d) {
            uint64_t tot = 0, mx = 0;
            long n = 0;
            double spent = 0;
            for (uint32_t r = 0; r < STATES; ++r) {
                if (dist[r] != d)
                    continue;
                if (d < 11) {
                    seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
                    if ((seed >> 33) % (uint64_t) (cnt[d] / 3000 + 1))
                        continue;
                }
                state_t s;
                unrank_state(r, &s);
                double t0 = now_ns();
                int len = search(&s);
                spent += now_ns() - t0;
                if (len != d)
                    bad_total++;
                ++n;
                tot += nodes;
                mx = nodes > mx ? nodes : mx;
            }
            printf("%-3d %8ld %12.0f %10llu %14llu %10.1f %9.1f\n", d, n,
                   (double) tot / n, (unsigned long long) mx,
                   (unsigned long long) tot, spent / 1e6, spent / (double) tot);
        }
        printf("wrong lengths: %ld\n", bad_total);
        return bad_total != 0;
    }

    long viol = 0;
    for (uint32_t r = 0; r < STATES; ++r) {   /* H1 on the packed accessors */
        state_t s;
        unrank_state(r, &s);
        uint8_t loc[3];
        state_loc(&s, loc);
        viol += (int) pdb_get(pdb_idx(rank_orient(s.o), loc_index(loc))) > dist[r];
    }
    printf("H1 violations: %ld\n", viol);
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
        int d = search(&s);
        bad += d != dist[r] || !is_solved_after(&s, path, d);
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
           (double) tot11 / n11, (unsigned long long) mx11);
    return 0;
}
