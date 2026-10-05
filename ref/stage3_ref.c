/* GCC reference for Stage 4: the search of stage3.c (same IDA*, same tables,
 * same frame layout), freestanding so that it runs on Ripes without a libc.
 * Differences from stage3.c, none of which add work to the search:
 *   - tables are const arrays from tables.h (tools/gen_stage3_tables.py --c)
 *   - the node counter is dropped (the assembly has none either)
 *   - the state is a compile-time string: -DSTATE=\"21345671111111\"
 * The program parses it, searches, replays the path on the full model and
 * returns 0 if the replay is solved, 1 otherwise. No printing, so compare
 * the assembly's count minus its solved-cube count (printing overhead).
 * -DQUICK replaces the full replay at h == 0 by the cheaper test of stage3.s
 * (follow cubies 3..6 through dest[][]), so that the compiler is compared with
 * the hand-written code on the same algorithm.
 * Build: see measure/build_ref.sh
 */
#include <stdint.h>
#include <stddef.h>

/* GCC lowers the 14-byte state_t copy in is_solved_after to a memcpy call and
 * there is no rv32i libc here, so supply the plain byte loop a freestanding
 * build needs. Its instructions are part of the reference count. */
__attribute__((optimize("no-tree-loop-distribute-patterns")))
void *memcpy(void *dst, const void *src, size_t n)
{
    uint8_t *d = dst;
    const uint8_t *s = src;
    while (n--)
        *d++ = *s++;
    return dst;
}

enum { CUBIES = 7, ORIENTS = 729, MOVES = 9, LOCS = 210, MAXD = 12 };
typedef struct { uint8_t p[CUBIES], o[CUBIES]; } state_t;

static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6}, {0, 1, 2, 4, 5, 6, 3}, {0, 2, 5, 3, 1, 4, 6}};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0}, {0, 0, 0, 1, 2, 1, 2}, {0, 0, 0, 0, 0, 0, 0}};

#include "tables.h"

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
static uint32_t rank_orient(const uint8_t *o)
{
    uint32_t r = 0;
    for (int i = 0; i < 6; ++i)
        r = r * 3 + o[i];
    return r;
}
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
static inline uint32_t pdb_idx(uint32_t o, uint32_t l)
{
    return (o << 7) + (o << 6) + (o << 4) + (o << 1) + l;
}
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

#ifdef QUICK
static const uint8_t dest[3][8] = {{3, 0, 2, 4, 1, 5, 6, 0},
                                   {0, 1, 2, 6, 3, 4, 5, 0},
                                   {0, 4, 1, 3, 5, 2, 6, 0}};
static uint8_t rloc[CUBIES]; /* root slot of every cubie */

static int quick_solved(int n)
{
    uint32_t a = rloc[3], b = rloc[4], c = rloc[5], e = rloc[6];
    for (int i = 0; i < n; ++i) {
        int m = path[i], f = 0;
        if (m >= 3) {
            f = 1;
            m -= 3;
        }
        if (m >= 3) {
            f = 2;
            m -= 3;
        }
        for (int t = 0; t <= m; ++t) {
            a = dest[f][a];
            b = dest[f][b];
            c = dest[f][c];
            e = dest[f][e];
        }
    }
    return a == 3 && b == 4 && c == 5 && e == 6;
}
#define SOLVED_AFTER(root, n) quick_solved(n)
#else
#define SOLVED_AFTER(root, n) is_solved_after(root, path, n)
#endif

static int search(const state_t *root)
{
    uint8_t loc[3];
    state_loc(root, loc);
#ifdef QUICK
    for (int j = 0; j < CUBIES; ++j)
        rloc[root->p[j]] = (uint8_t) j;
#endif
    uint32_t o0 = rank_orient(root->o), l0 = loc_index(loc);
    int h0 = (int) pdb_get(pdb_idx(o0, l0));
    if (h0 == 0 && SOLVED_AFTER(root, 0))
        return 0;
    for (int bound = h0;; ++bound) {
        uint16_t no[MAXD + 1], co[MAXD + 1];
        uint8_t nl[MAXD + 1], cl[MAXD + 1];
        uint8_t face[MAXD + 1], turn[MAXD + 1], last[MAXD + 1];
        int d = 0;
        no[0] = co[0] = (uint16_t) o0;
        nl[0] = cl[0] = (uint8_t) l0;
        face[0] = turn[0] = 0;
        last[0] = 4;
        for (;;) {
            if (turn[d] == 3) {
                turn[d] = 0;
                ++face[d];
                co[d] = no[d];
                cl[d] = nl[d];
            }
            if (face[d] == 3) {
                if (d == 0)
                    break;
                --d;
                continue;
            }
            if (face[d] == last[d]) {
                ++face[d];
                continue;
            }
            uint32_t f = face[d];
            co[d] = onext[f][co[d]];
            cl[d] = lnext[f][cl[d]];
            path[d] = (uint8_t) ((f << 1) + f + turn[d]);
            ++turn[d];
            int h = (int) pdb_get(pdb_idx(co[d], cl[d]));
            if (d + 1 + h > bound)
                continue;
            if (h == 0 && SOLVED_AFTER(root, d + 1))
                return d + 1;
            if (d + 1 == bound)
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

int main(void)
{
    static const char text[] = STATE;
    state_t s;
    for (int i = 0; i < 7; ++i) {
        s.p[i] = (uint8_t) (text[i] - '1');
        s.o[i] = (uint8_t) (text[i + 7] - '1');
    }
    int d = search(&s);
    return !is_solved_after(&s, path, d);
}
