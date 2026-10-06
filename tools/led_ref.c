/* Host reference for the LED-matrix renderer of stage5.s.
 *
 *   led_ref selftest          check the facelet model against the move tables
 *   led_ref tables            print the .data tables that stage5.s needs
 *   led_ref check <file>      compare the frames printed by the dump build of
 *                             stage5.s (Ripes output) with frames computed by
 *                             rotating 24 stickers in 3-D, independent of the
 *                             solver's tables
 *
 * The geometric model moves stickers, not cubies: a sticker is a position
 * vector plus a face normal, and a face turn rotates both. Nothing here reads
 * the solver's source/twist tables except selftest, which uses them to fix the
 * meaning of the orientation digit.
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 35
#define H 25

typedef struct {
    int p[3], n[3], col;
} sticker_t;
typedef struct {
    sticker_t s[24];
} cube_t;

/* positions 0..7 as in the README: x +1 = right, y +1 = up, z +1 = front */
static const int POS[8][3] = {{-1, 1, 1}, {1, 1, 1},  {1, -1, 1}, {-1, -1, 1},
                              {1, 1, -1}, {1, -1, -1}, {-1, -1, -1}, {-1, 1, -1}};
/* colour 0..5: U white, D yellow, F green, B blue, R red, L orange */
static const char CHAR_OF[6] = {'W', 'Y', 'G', 'B', 'R', 'O'};
static const unsigned RGB[6] = {0xFFFFFFu, 0xFFFF00u, 0x00B000u,
                                0x0000FFu, 0xFF0000u, 0xFF7000u};

/* solver.c tables, used by selftest only */
static const int SOURCE[3][7] = {
    {1, 4, 2, 0, 3, 5, 6}, {0, 1, 2, 4, 5, 6, 3}, {0, 2, 5, 3, 1, 4, 6}};
static const int TWIST[3][7] = {
    {1, 2, 0, 2, 1, 0, 0}, {0, 0, 0, 1, 2, 1, 2}, {0, 0, 0, 0, 0, 0, 0}};

static int face_colour(const int n[3])
{
    if (n[1] == 1) return 0;
    if (n[1] == -1) return 1;
    if (n[2] == 1) return 2;
    if (n[2] == -1) return 3;
    return n[0] == 1 ? 4 : 5;
}

static cube_t solved(void)
{
    cube_t c;
    int k = 0;
    for (int q = 0; q < 8; q++)
        for (int a = 0; a < 3; a++) {
            sticker_t *s = &c.s[k++];
            memcpy(s->p, POS[q], sizeof s->p);
            memset(s->n, 0, sizeof s->n);
            s->n[a] = POS[q][a];
            s->col = face_colour(s->n);
        }
    return c;
}

/* quarter turn clockwise seen from outside the face; f = 0 R, 1 B, 2 D */
static void rot_vec(int f, int v[3])
{
    int x = v[0], y = v[1], z = v[2];
    if (f == 0) { v[1] = z; v[2] = -y; }
    else if (f == 1) { v[0] = -y; v[1] = x; }
    else { v[0] = z; v[2] = -x; }
}

static void quarter(cube_t *c, int f)
{
    for (int i = 0; i < 24; i++) {
        sticker_t *s = &c->s[i];
        int in_layer = f == 0 ? s->p[0] == 1 : f == 1 ? s->p[2] == -1 : s->p[1] == -1;
        if (!in_layer) continue;
        rot_vec(f, s->p);
        rot_vec(f, s->n);
    }
}

static void apply_move(cube_t *c, int m) /* m = 3 f + turns - 1 */
{
    for (int i = 0; i <= m % 3; i++) quarter(c, m / 3);
}

/* the three face normals at position q, UD face first, then clockwise seen
 * from outside the corner; used as the index k of a facelet */
static void face_list(int q, int L[3][3])
{
    int ud[3] = {0, POS[q][1], 0}, x[3] = {POS[q][0], 0, 0}, z[3] = {0, 0, POS[q][2]};
    /* det of the rows (ud, x, z) is -ud.y * x.x * z.z */
    int det = -ud[1] * x[0] * z[2];
    int swap = det < 0;
    memcpy(L[0], ud, sizeof ud);
    memcpy(L[1], swap ? z : x, sizeof ud);
    memcpy(L[2], swap ? x : z, sizeof ud);
}

/* net cell (fx, fy) of a sticker, 8 x 6 facelets */
static void net_cell(const sticker_t *s, int *fx, int *fy)
{
    int x = s->p[0], y = s->p[1], z = s->p[2];
    int c = s->col, col, row, sx, sy;
    if (c == 0) { sx = 1; sy = 0; col = (x + 1) / 2; row = z == -1 ? 0 : 1; }
    else if (c == 2) { sx = 1; sy = 1; col = (x + 1) / 2; row = y == 1 ? 0 : 1; }
    else if (c == 5) { sx = 0; sy = 1; col = z == -1 ? 0 : 1; row = y == 1 ? 0 : 1; }
    else if (c == 4) { sx = 2; sy = 1; col = z == 1 ? 0 : 1; row = y == 1 ? 0 : 1; }
    else if (c == 3) { sx = 3; sy = 1; col = x == 1 ? 0 : 1; row = y == 1 ? 0 : 1; }
    else { sx = 1; sy = 2; col = (x + 1) / 2; row = z == 1 ? 0 : 1; }
    *fx = sx * 2 + col;
    *fy = sy * 2 + row;
}

/* the face a sticker lies on is its normal, not its colour */
static void net_cell_of(const int pos[3], const int n[3], int *fx, int *fy)
{
    sticker_t s;
    memcpy(s.p, pos, sizeof s.p);
    memcpy(s.n, n, sizeof s.n);
    s.col = face_colour(n);
    net_cell(&s, fx, fy);
}

static void pixel_of(int fx, int fy, int *px, int *py)
{
    *px = fx * 4 + fx / 2;
    *py = fy * 3 + fy / 2;
}

static void draw_block(unsigned char fb[H][W], int fx, int fy, unsigned char ch)
{
    int px, py;
    pixel_of(fx, fy, &px, &py);
    for (int dy = 0; dy < 3; dy++)
        for (int dx = 0; dx < 4; dx++) fb[py + dy][px + dx] = ch;
}

static void render_geometry(const cube_t *c, unsigned char fb[H][W])
{
    memset(fb, '.', H * W);
    for (int i = 0; i < 24; i++) {
        int fx, fy;
        net_cell_of(c->s[i].p, c->s[i].n, &fx, &fy);
        draw_block(fb, fx, fy, (unsigned char) CHAR_OF[c->s[i].col]);
    }
}

/* (p, o) of every slot, derived from the stickers; tau selects the sign of o */
static void derive_po(const cube_t *c, int tau, int p[8], int o[8])
{
    for (int q = 0; q < 8; q++) {
        int L[3][3], cols[3], k_of_col[6];
        face_list(q, L);
        memset(k_of_col, -1, sizeof k_of_col);
        for (int i = 0; i < 24; i++) {
            if (memcmp(c->s[i].p, POS[q], sizeof(int) * 3)) continue;
            for (int k = 0; k < 3; k++)
                if (!memcmp(c->s[i].n, L[k], sizeof(int) * 3)) {
                    cols[k] = c->s[i].col;
                    k_of_col[c->s[i].col] = k;
                }
        }
        p[q] = -1;
        for (int h = 0; h < 8; h++) {
            int HL[3][3], seen = 0;
            face_list(h, HL);
            for (int j = 0; j < 3; j++) seen |= 1 << face_colour(HL[j]);
            if (seen == ((1 << cols[0]) | (1 << cols[1]) | (1 << cols[2]))) p[q] = h;
        }
        int ref;
        {
            int HL[3][3];
            face_list(p[q], HL);
            ref = face_colour(HL[0]);
        }
        o[q] = (tau * k_of_col[ref]) % 3;
    }
}

/* what stage5.s draws: facelet (q, k) shows colour_tbl[C][o][k] */
static int tau_global = 1;
static int colour_tbl(int C, int o, int k)
{
    int L[3][3];
    face_list(C, L);
    return face_colour(L[((k - tau_global * o) % 3 + 3) % 3]);
}

static void render_model(const int p[8], const int o[8], unsigned char fb[H][W])
{
    memset(fb, '.', H * W);
    for (int q = 0; q < 8; q++) {
        int L[3][3];
        face_list(q, L);
        for (int k = 0; k < 3; k++) {
            int fx, fy;
            net_cell_of(POS[q], L[k], &fx, &fy);
            draw_block(fb, fx, fy, (unsigned char) CHAR_OF[colour_tbl(p[q], o[q], k)]);
        }
    }
}

static int rnd(int n) { return rand() % n; }

static int selftest(void)
{
    int good_tau = 0;
    /* 1. rotations agree with the solver's source tables */
    for (int f = 0; f < 3; f++) {
        cube_t c = solved();
        int p[8], o[8];
        quarter(&c, f);
        derive_po(&c, 1, p, o);
        for (int i = 0; i < 7; i++)
            if (p[i + 1] != SOURCE[f][i] + 1) {
                printf("FAIL: face %d slot %d takes cubie %d, table says %d\n", f, i, p[i + 1] - 1,
                       SOURCE[f][i]);
                return 1;
            }
    }
    /* 2. pick the sign of the orientation digit that matches the twist tables */
    for (int tau = 1; tau <= 2 && !good_tau; tau++) {
        int ok = 1;
        for (int trial = 0; trial < 3000 && ok; trial++) {
            cube_t c = solved();
            int p[8], o[8];
            int len = 1 + rnd(14);
            for (int i = 0; i < len; i++) apply_move(&c, rnd(9));
            derive_po(&c, tau, p, o);
            for (int f = 0; f < 3 && ok; f++) {
                cube_t d = c;
                int p2[8], o2[8];
                quarter(&d, f);
                derive_po(&d, tau, p2, o2);
                for (int i = 0; i < 7; i++) {
                    if (p2[i + 1] != p[SOURCE[f][i] + 1]) ok = 0;
                    if (o2[i + 1] != (o[SOURCE[f][i] + 1] + TWIST[f][i]) % 3) ok = 0;
                }
            }
        }
        if (ok) good_tau = tau;
    }
    if (!good_tau) { puts("FAIL: no orientation sign matches the twist tables"); return 1; }
    fprintf(stderr, "orientation digit o = tau * (index of the U/D sticker), tau = %d\n", good_tau);
    tau_global = good_tau;
    /* 3. the table-driven renderer equals the sticker renderer */
    for (int trial = 0; trial < 3000; trial++) {
        cube_t c = solved();
        int p[8], o[8];
        unsigned char a[H][W], b[H][W];
        int len = rnd(15);
        for (int i = 0; i < len; i++) apply_move(&c, rnd(9));
        derive_po(&c, good_tau, p, o);
        render_geometry(&c, a);
        render_model(p, o, b);
        if (memcmp(a, b, sizeof a)) { puts("FAIL: renderer mismatch"); return 1; }
    }
    /* 4. every move changes the picture, so animation steps are visible */
    for (int m = 0; m < 9; m++) {
        cube_t c = solved(), d = solved();
        unsigned char a[H][W], b[H][W];
        apply_move(&d, m);
        render_geometry(&c, a);
        render_geometry(&d, b);
        if (!memcmp(a, b, sizeof a)) { printf("FAIL: move %d draws no change\n", m); return 1; }
    }
    fputs("selftest ok\n", stderr);
    return 0;
}

static void tables(void)
{
    if (selftest()) exit(1);
    printf("# GENERATED by tools/led_ref.c tables: do not edit\n");
    printf("xy_tbl:                                 # per position q, face index k: x0 y0 pixels\n");
    for (int q = 0; q < 8; q++) {
        int L[3][3];
        face_list(q, L);
        printf("        .byte  ");
        for (int k = 0; k < 3; k++) {
            int fx, fy, px, py;
            net_cell_of(POS[q], L[k], &fx, &fy);
            pixel_of(fx, fy, &px, &py);
            printf("%s %d, %d", k ? "," : "", px, py);
        }
        printf("\n");
    }
    printf("colour_tbl:                             # per cubie C, orientation o, face index k: colour 0..5\n");
    for (int c = 0; c < 8; c++)
        for (int o = 0; o < 3; o++)
            printf("        .byte   %d, %d, %d\n", colour_tbl(c, o, 0), colour_tbl(c, o, 1),
                   colour_tbl(c, o, 2));
    printf("        .align  2\n");
    printf("colors:                                 # W Y G B R O as 0x00RRGGBB\n");
    for (int i = 0; i < 6; i++) printf("        .word   0x%06X\n", RGB[i]);
    printf("# END GENERATED LED TABLES\n");
}

static int parse_move(const char *t)
{
    int f = t[0] == 'R' ? 0 : t[0] == 'B' ? 1 : t[0] == 'D' ? 2 : -1;
    if (f < 0) return -1;
    if (t[1] == 0) return 3 * f;
    if (t[1] == '2' && !t[2]) return 3 * f + 1;
    if (t[1] == '\'' && !t[2]) return 3 * f + 2;
    return -1;
}

static void print_frame(unsigned char fb[H][W])
{
    for (int y = 0; y < H; y++) printf("    %.*s\n", W, fb[y]);
}

/* read the whole file, dropping the NUL bytes Ripes appends to every string */
static char *slurp(const char *name, size_t *len)
{
    FILE *f = fopen(name, "rb");
    if (!f) { perror(name); exit(2); }
    size_t cap = 1 << 16, n = 0;
    char *b = malloc(cap);
    int ch;
    while ((ch = fgetc(f)) != EOF) {
        if (ch == 0 || ch == '\r') continue;
        if (n + 2 > cap) b = realloc(b, cap *= 2);
        b[n++] = (char) ch;
    }
    b[n] = 0;
    fclose(f);
    *len = n;
    return b;
}

static int check(const char *name)
{
    size_t len;
    char *txt = slurp(name, &len), *save = NULL;
    int frames = 0, cases = 0, bad = 0;
    static unsigned char got[64][H][W];
    for (char *line = strtok_r(txt, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        if (!strcmp(line, "FRAME")) {
            if (frames >= 64) { puts("too many frames"); return 1; }
            for (int y = 0; y < H; y++) {
                line = strtok_r(NULL, "\n", &save);
                if (!line || (int) strlen(line) != W) { puts("FAIL: malformed frame"); return 1; }
                memcpy(got[frames][y], line, W);
            }
            frames++;
        } else if (!strncmp(line, "[PASS] ", 7) || !strncmp(line, "[FAIL] ", 7)) {
            char state[32] = "", *moves;
            int n = -1;
            if (sscanf(line + 7, "%31s : %d moves:", state, &n) < 2) {
                printf("case %s: no solution line, %d frames\n", state, frames);
                bad += frames != 0;
                frames = 0;
                continue;
            }
            moves = strstr(line, "moves:") + 6;
            int mv[16], nm = 0;
            for (char *t = strtok(moves, " "); t; t = strtok(NULL, " ")) mv[nm++] = parse_move(t);
            if (nm != n) { printf("case %s: move count mismatch\n", state); bad++; frames = 0; continue; }
            /* scramble = solved with the inverse moves applied in reverse order */
            cube_t c = solved();
            for (int i = nm - 1; i >= 0; i--) {
                int f = mv[i] / 3, t = mv[i] % 3 + 1;
                for (int j = 0; j < 4 - t; j++) quarter(&c, f);
            }
            /* the digit string must describe that scramble */
            int p[8], o[8], digits_ok = 1;
            derive_po(&c, tau_global, p, o);
            for (int i = 0; i < 7; i++) {
                if (state[i] != '0' + p[i + 1]) digits_ok = 0;
                if (state[7 + i] != '1' + o[i + 1]) digits_ok = 0;
            }
            int ok = frames == nm + 1 && digits_ok;
            for (int k = 0; ok && k <= nm; k++) {
                unsigned char exp[H][W];
                render_geometry(&c, exp);
                if (memcmp(exp, got[k], sizeof exp)) {
                    printf("case %s: frame %d differs\n  expected:\n", state, k);
                    print_frame(exp);
                    printf("  got:\n");
                    print_frame(got[k]);
                    ok = 0;
                }
                if (k < nm) apply_move(&c, mv[k]);
            }
            printf("case %s: %d moves, %d frames, digits %s: %s\n", state, nm, frames,
                   digits_ok ? "match" : "MISMATCH", ok ? "OK" : "FAIL");
            cases++;
            bad += !ok;
            frames = 0;
        }
    }
    printf("%d case(s) checked, %d failed\n", cases, bad);
    return cases == 0 || bad != 0;
}

int main(int argc, char **argv)
{
    if (argc >= 2 && !strcmp(argv[1], "selftest")) return selftest();
    if (argc >= 2 && !strcmp(argv[1], "tables")) { tables(); return 0; }
    if (argc >= 3 && !strcmp(argv[1], "check")) {
        if (selftest()) return 1;
        return check(argv[2]);
    }
    fprintf(stderr, "usage: led_ref selftest | tables | check <ripes-output>\n");
    return 2;
}
