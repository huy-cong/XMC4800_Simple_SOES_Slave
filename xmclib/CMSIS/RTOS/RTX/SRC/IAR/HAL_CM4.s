/*----------------------------------------------------------------------------
 *      CMSIS-RTOS  -  RTX
 *----------------------------------------------------------------------------
 *      Name:    HAL_CM4.S
 *      Purpose: Hardware Abstraction Layer for Cortex-M4
 *      Rev.:    V4.79
 *----------------------------------------------------------------------------
 *
 * Copyright (c) 1999-2009 KEIL, 2009-2015 ARM Germany GmbH
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *  - Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  - Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  - Neither the name of ARM  nor the names of its contributors may be used 
 *    to endorse or promote products derived from this software without 
 *    specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL COPYRIGHT HOLDERS AND CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *---------------------------------------------------------------------------*/

        NAME    HAL_CM4.S

        #define TCB_STACKF 37
        #define TCB_TSTACK 40

        EXTERN  os_flags
        EXTERN  os_tsk
        EXTERN  rt_alloc_box
        EXTERN  rt_free_box
        EXTERN  rt_stk_check
        EXTERN  rt_pop_req
        EXTERN  rt_systick
        EXTERN  os_tick_irqack
        EXTERN  SVC_Table
        EXTERN  SVC_Count

/*----------------------------------------------------------------------------
 *      Functions
 *---------------------------------------------------------------------------*/

        SECTION .text:CODE:NOROOT(2)
        THUMB

/*--------------------------- rt_set_PSP ------------------------------------*/

;       void rt_set_PSP (U32 stack);

        PUBLIC  rt_set_PSP
rt_set_PSP:

        MSR     PSP,R0
        BX      LR


/*--------------------------- rt_get_PSP ------------------------------------*/

;       U32 rt_get_PSP (void);

        PUBLIC  rt_get_PSP
rt_get_PSP:

        MRS     R0,PSP
        BX      LR


/*--------------------------- os_set_env ------------------------------------*/

;       void os_set_env (void);
        /* Switch to Unprivileged/Privileged Thread mode, use PSP. */

        PUBLIC  os_set_env
os_set_env:

        MOV     R0,SP                   /* PSP = MSP */
        MSR     PSP,R0
        LDR     R0,=os_flags
        LDRB    R0,[R0]
        LSLS    R0,#31
        ITE     NE
        MOVNE   R0,#0x02                /* Privileged Thread mode, use PSP */
        MOVEQ   R0,#0x03                /* Unprivileged Thread mode, use PSP */
        MSR     CONTROL,R0
        BX      LR


/*--------------------------- _alloc_box ------------------------------------*/

;      void *_alloc_box (void *box_mem);
       /* Function wrapper for Unprivileged/Privileged mode. */

        PUBLIC  _alloc_box
_alloc_box:

        LDR     R12,=rt_alloc_box
        MRS     R3,IPSR
        LSLS    R3,#24
        IT      NE
        BXNE    R12
        MRS     R3,CONTROL
        LSLS    R3,#31
        IT      EQ
        BXEQ    R12
        SVC     0
        BX      LR


/*--------------------------- _free_box -------------------------------------*/

;       U32 _free_box (void *box_mem, void *box);
        /* Function wrapper for Unprivileged/Privileged mode. */

        PUBLIC  _free_box
_free_box:

        LDR     R12,=rt_free_box
        MRS     R3,IPSR
        LSLS    R3,#24
        IT      NE
        BXNE    R12
        MRS     R3,CONTROL
        LSLS    R3,#31
        IT      EQ
        BXEQ    R12
        SVC     0
        BX      LR


/*-------------------------- SVC_Handler ------------------------------------*/

;       void SVC_Handler (void);

        PUBLIC  SVC_Handler
SVC_Handler:

        MRS     R0,PSP                  /* Read PSP */
        LDR     R1,[R0,#24]             /* Read Saved PC from Stack */
        LDRB    R1,[R1,#-2]             /* Load SVC Number */
        CBNZ    R1,SVC_User

        LDM     R0,{R0-R3,R12}          /* Read R0-R3,R12 from stack */
        PUSH    {R4,LR}                 /* Save EXC_RETURN */
        BLX     R12                     /* Call SVC Function */
        POP     {R4,LR}                 /* Restore EXC_RETURN */

        MRS     R12,PSP                 /* Read PSP */
        STM     R12,{R0-R2}             /* Store return values */

        LDR     R3,=os_tsk
        LDM     R3,{R1,R2}              /* os_tsk.run, os_tsk.next */
        CMP     R1,R2
        IT      EQ
        BXEQ    LR                      /* RETI, no task switch */

        CBNZ    R1,SVC_ContextSave      /* Runtask not deleted? */

        TST     LR,#0x10                /* is it extended frame? */
        BNE     SVC_ContextRestore
        LDR     R1,=0xE000EF34
        LDR     R0,[R1]                 /* Load FPCCR */
        BIC     R0,R0,#1                /* Clear LSPACT (Lazy state) */
        STR     R0,[R1]                 /* Store FPCCR */
        B       SVC_ContextRestore

SVC_ContextSave:
        TST     LR,#0x10                /* is it extended frame? */
        ITTE    EQ
        VSTMDBEQ R12!,{S16-S31}         /* yes, stack also VFP hi-regs */
        MOVEQ   R0,#0x01                /* os_tsk->stack_frame val */
        MOVNE   R0,#0x00
        STRB    R0,[R1,#TCB_STACKF]     /* os_tsk.run->stack_frame = val */
        STMDB   R12!,{R4-R11}           /* Save Old context */
        STR     R12,[R1,#TCB_TSTACK]    /* Update os_tsk.run->tsk_stack */

        PUSH    {R2,R3}
        BL      rt_stk_check            /* Check for Stack overflow */
        POP     {R2,R3}

SVC_ContextRestore:
        STR     R2,[R3]                 /* os_tsk.run = os_tsk.next */

        LDR     R12,[R2,#TCB_TSTACK]    /* os_tsk.next->tsk_stack */
        LDMIA   R12!,{R4-R11}           /* Restore New Context */
        LDRB    R0,[R2,#TCB_STACKF]     /* Stack Frame */
        CMP     R0,#0                   /* Basic/Extended Stack Frame */
        ITEE    EQ
        MVNEQ   LR,#~0xFFFFFFFD         /* set EXC_RETURN value */
        MVNNE   LR,#~0xFFFFFFED
        VLDMIANE R12!,{S16-S31}         /* restore VFP hi-registers */
        MSR     PSP,R12                 /* Write PSP */

SVC_Exit:
        BX      LR

        /*------------------- User SVC ------------------------------*/

SVC_User:
        PUSH    {R4,LR}                 /* Save Registers */
        LDR     R2,=SVC_Count
        LDR     R2,[R2]
        CMP     R1,R2
        BHI     SVC_Done                /* Overflow */

        LDR     R4,=SVC_Table-4
        LDR     R4,[R4,R1,LSL #2]       /* Load SVC Function Address */

        LDM     R0,{R0-R3,R12}          /* Read R0-R3,R12 from stack */
        BLX     R4                      /* Call SVC Function */

        MRS     R12,PSP
        STM     R12,{R0-R3}             /* Function return values */
SVC_Done:
        POP     {R4,PC}                 /* RETI */
        

/*-------------------------- PendSV_Handler ---------------------------------*/

;       void PendSV_Handler (void);

        PUBLIC  PendSV_Handler
PendSV_Handler:

        PUSH    {R4,LR}                 /* Save EXC_RETURN */
        BL      rt_pop_req

Sys_Switch:
        POP     {R4,LR}                 /* Restore EXC_RETURN */

        LDR     R3,=os_tsk
        LDM     R3,{R1,R2}              /* os_tsk.run, os_tsk.next */
        CMP     R1,R2
        IT      EQ
        BXEQ    LR                      /* RETI, no task switch */

        MRS     R12,PSP                 /* Read PSP */
        TST     LR,#0x10                /* is it extended frame? */
        ITTE    EQ
        VSTMDBEQ R12!,{S16-S31}         /* yes, stack also VFP hi-regs */
        MOVEQ   R0,#0x01                /* os_tsk->stack_frame val */
        MOVNE   R0,#0x00
        STRB    R0,[R1,#TCB_STACKF]     /* os_tsk.run->stack_frame = val */
        STMDB   R12!,{R4-R11}           /* Save Old context */
        STR     R12,[R1,#TCB_TSTACK]    /* Update os_tsk.run->tsk_stack */

        PUSH    {R2,R3}
        BL      rt_stk_check            /* Check for Stack overflow */
        POP     {R2,R3}

        STR     R2,[R3]                 /* os_tsk.run = os_tsk.next */

        LDR     R12,[R2,#TCB_TSTACK]    /* os_tsk.next->tsk_stack */
        LDMIA   R12!,{R4-R11}           /* Restore New Context */
        LDRB    R0,[R2,#TCB_STACKF]     /* Stack Frame */
        CMP     R0,#0                   /* Basic/Extended Stack Frame */
        ITEE    EQ
        MVNEQ   LR,#~0xFFFFFFFD         /* set EXC_RETURN value */
        MVNNE   LR,#~0xFFFFFFED
        VLDMIANE R12!,{S16-S31}         /* restore VFP hi-registers */
        MSR     PSP,R12                 /* Write PSP */

Sys_Exit:
        BX      LR                      /* Return to Thread Mode */


/*-------------------------- SysTick_Handler --------------------------------*/

;       void SysTick_Handler (void);

        PUBLIC  SysTick_Handler
SysTick_Handler:

        PUSH    {R4,LR}                 /* Save EXC_RETURN */
        BL      rt_systick
        B       Sys_Switch


/*-------------------------- OS_Tick_Handler --------------------------------*/

;       void OS_Tick_Handler (void);

        PUBLIC  OS_Tick_Handler
OS_Tick_Handler:

        PUSH    {R4,LR}                 /* Save EXC_RETURN */
        BL      os_tick_irqack
        BL      rt_systick
        B       Sys_Switch


        END

/*----------------------------------------------------------------------------
 * end of file
 *---------------------------------------------------------------------------*/
