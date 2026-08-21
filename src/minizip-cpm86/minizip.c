#include <ctype.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ENTRIES 128
#define NAME_LEN 32
#define COPY_BUF 1024

struct entry {
    char name[NAME_LEN];
    unsigned long crc;
    unsigned long size;
    unsigned long local_off;
};

static unsigned long crc_table[256];
static struct entry entries[MAX_ENTRIES];
static int nentries;

static void put16(FILE *f, unsigned short v)
{
    fputc((int)(v & 0xff), f);
    fputc((int)((v >> 8) & 0xff), f);
}

static void put32(FILE *f, unsigned long v)
{
    put16(f, (unsigned short)(v & 0xffffUL));
    put16(f, (unsigned short)((v >> 16) & 0xffffUL));
}

static unsigned long tell32(FILE *f)
{
    long p = ftell(f);
    if (p < 0) {
        fprintf(stderr, "zip: ftell failed\n");
        exit(1);
    }
    return (unsigned long)p;
}

static void crc_init(void)
{
    unsigned i;
    for (i = 0; i < 256; ++i) {
        unsigned long c = i;
        int k;
        for (k = 0; k < 8; ++k)
            c = (c & 1) ? (0xedb88320UL ^ (c >> 1)) : (c >> 1);
        crc_table[i] = c;
    }
}

static unsigned long crc_update(unsigned long crc,
                                const unsigned char *buf, unsigned len)
{
    while (len--)
        crc = crc_table[(unsigned char)(crc ^ *buf++)] ^ (crc >> 8);
    return crc;
}

static void zip_name(char *dst, const char *src)
{
    const char *p = strchr(src, ':');
    size_t i = 0;

    src = p ? p + 1 : src;
    while (*src && i + 1 < NAME_LEN) {
        char c = *src++;
        if (c == '\\')
            c = '/';
        dst[i++] = (char)tolower((unsigned char)c);
    }
    dst[i] = '\0';
}

static void output_name(char *dst, const char *src)
{
    size_t n;

    n = strlen(src);
    if (n >= NAME_LEN) {
        fprintf(stderr, "zip: archive name too long: %s\n", src);
        exit(1);
    }
    strcpy(dst, src);
    if (n < 4 || dst[n - 4] != '.') {
        if (n + 4 >= NAME_LEN) {
            fprintf(stderr, "zip: archive name too long: %s\n", src);
            exit(1);
        }
        strcat(dst, ".ZIP");
    }
}

static void write_local_placeholder(FILE *out, const char *name)
{
    size_t namelen = strlen(name);

    put32(out, 0x04034b50UL);
    put16(out, 10);
    put16(out, 0);
    put16(out, 0);
    put16(out, 0);
    put16(out, 33);           /* 1980-01-01 00:00:00 */
    put32(out, 0);
    put32(out, 0);
    put32(out, 0);
    put16(out, (unsigned short)namelen);
    put16(out, 0);
    fwrite(name, 1, namelen, out);
}

static void patch_local(FILE *out, const struct entry *e)
{
    fseek(out, (long)e->local_off + 14, SEEK_SET);
    put32(out, e->crc);
    put32(out, e->size);
    put32(out, e->size);
    fseek(out, 0, SEEK_END);
}

static void add_file(FILE *out, const char *path)
{
    unsigned char buf[COPY_BUF];
    struct entry *e;
    FILE *in;
    size_t n;

    if (nentries >= MAX_ENTRIES) {
        fprintf(stderr, "zip: too many files (max %d)\n", MAX_ENTRIES);
        exit(1);
    }
    in = fopen(path, "rb");
    if (!in) {
        fprintf(stderr, "zip: cannot open %s\n", path);
        exit(1);
    }

    e = &entries[nentries++];
    zip_name(e->name, path);
    e->crc = 0xffffffffUL;
    e->size = 0;
    e->local_off = tell32(out);
    write_local_placeholder(out, e->name);

    while ((n = fread(buf, 1, sizeof(buf), in)) != 0) {
        e->crc = crc_update(e->crc, buf, (unsigned)n);
        e->size += (unsigned long)n;
        if (fwrite(buf, 1, n, out) != n) {
            fprintf(stderr, "zip: write failed\n");
            exit(1);
        }
    }
    fclose(in);
    e->crc ^= 0xffffffffUL;
    patch_local(out, e);
    printf("  adding: %s (stored 0%%)\n", e->name);
}

static int has_wild(const char *s)
{
    return strchr(s, '*') || strchr(s, '?');
}

static void add_arg(FILE *out, const char *arg)
{
    if (has_wild(arg)) {
        DIR *d = opendir((char *)arg);
        struct dirent *de;
        char prefix[3] = "";

        if (arg[0] && arg[1] == ':') {
            prefix[0] = arg[0];
            prefix[1] = ':';
        }
        if (!d) {
            fprintf(stderr, "zip: name not matched: %s\n", arg);
            exit(1);
        }
        while ((de = readdir(d)) != NULL) {
            char path[NAME_LEN];
            if (strlen(prefix) + strlen(de->d_name) >= sizeof(path)) {
                fprintf(stderr, "zip: name too long: %s%s\n",
                        prefix, de->d_name);
                exit(1);
            }
            strcpy(path, prefix);
            strcat(path, de->d_name);
            add_file(out, path);
        }
        closedir(d);
    } else {
        add_file(out, arg);
    }
}

static void write_central(FILE *out)
{
    unsigned long cd_start = tell32(out);
    unsigned long cd_end;
    int i;

    for (i = 0; i < nentries; ++i) {
        struct entry *e = &entries[i];
        size_t namelen = strlen(e->name);

        put32(out, 0x02014b50UL);
        put16(out, 20);
        put16(out, 10);
        put16(out, 0);
        put16(out, 0);
        put16(out, 0);
        put16(out, 33);
        put32(out, e->crc);
        put32(out, e->size);
        put32(out, e->size);
        put16(out, (unsigned short)namelen);
        put16(out, 0);
        put16(out, 0);
        put16(out, 0);
        put16(out, 0);
        put32(out, 0);
        put32(out, e->local_off);
        fwrite(e->name, 1, namelen, out);
    }

    cd_end = tell32(out);
    put32(out, 0x06054b50UL);
    put16(out, 0);
    put16(out, 0);
    put16(out, (unsigned short)nentries);
    put16(out, (unsigned short)nentries);
    put32(out, cd_end - cd_start);
    put32(out, cd_start);
    put16(out, 0);
}

int main(int argc, char **argv)
{
    char outname[NAME_LEN];
    FILE *out;
    int i;

    if (argc < 3) {
        fprintf(stderr, "usage: zip archive file...\n");
        return 1;
    }

    crc_init();
    output_name(outname, argv[1]);
    out = fopen(outname, "wb");
    if (!out) {
        fprintf(stderr, "zip: cannot create %s\n", outname);
        return 1;
    }

    for (i = 2; i < argc; ++i)
        add_arg(out, argv[i]);
    write_central(out);
    fclose(out);

    return 0;
}
