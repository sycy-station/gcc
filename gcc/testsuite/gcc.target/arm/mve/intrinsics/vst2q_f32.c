/* { dg-require-effective-target arm_v8_1m_mve_fp_ok } */
/* { dg-add-options arm_v8_1m_mve_fp } */
/* { dg-additional-options "-O2" } */
/* { dg-final { check-function-bodies "**" "" } } */

#include "arm_mve.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
**foo:
**	...
**	vst20.32	{q[0-9]+, q[0-9]+}, \[(?:ip|fp|r[0-9]+)\](?:	@.*|)
**	...
**	vst21.32	{q[0-9]+, q[0-9]+}, \[(?:ip|fp|r[0-9]+)\](?:	@.*|)
**	...
*/
void
foo (float32_t *addr, float32x4x2_t value)
{
  vst2q_f32 (addr, value);
}


/*
**foo1:
**	...
**	vst20.32	{q[0-9]+, q[0-9]+}, \[(?:ip|fp|r[0-9]+)\](?:	@.*|)
**	...
**	vst21.32	{q[0-9]+, q[0-9]+}, \[(?:ip|fp|r[0-9]+)\](?:	@.*|)
**	...
*/
void
foo1 (float32_t *addr, float32x4x2_t value)
{
  vst2q (addr, value);
}

#ifdef __cplusplus
}
#endif

/* { dg-final { scan-assembler-not "__ARM_undef" } } */
