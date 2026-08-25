/* Dump the raw CP/M-86 command tail (base page 0x80) + argv, to test whether
   real CCP/M-86 (MAME) folds the command line to upper-case. Small model:
   DS = base page, so (char*)0x80 is the tail length, 0x81+ the chars. */
#include <stdio.h>
int main(int argc, char **argv)
{
    unsigned char *bp = (unsigned char *)0;   /* DS:0 = base page */
    unsigned char len = bp[0x80];
    int i;
    printf("RAWTAIL len=%u [", (unsigned)len);
    for(i = 0; i < len; i++) {
        unsigned char c = bp[0x81 + i];
        putchar(c ? c : '.');   /* show NUL (tokenizer) as '.' */
    }
    printf("]\r\n");
    printf("ARGC=%d", argc);
    for(i = 1; i < argc; i++) printf(" argv%d=[%s]", i, argv[i]);
    printf("\r\n");
    return 0;
}
