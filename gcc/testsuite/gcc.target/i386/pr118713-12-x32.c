/* { dg-do compile { target *-*-linux* } } */
/* { dg-require-effective-target maybe_x32 } */
/* { dg-options "-O2 -mx32 -fno-pic -fno-plt -mindirect-branch-register" } */

#include "pr118713-12.c"

/* { dg-final { scan-assembler "movl\[ \t\]*bar@GOTPCREL" } } */
/* { dg-final { scan-assembler "call\[ \t\]*\\*%" } } */
