extern MULTIBOOT_MAIN
global _multiboot_main

section .multiboot_header
header_start:
    dd 0xe85250d6                ; magic number (multiboot 2)
    dd 0                         ; architecture 0 (protected mode i386)
    dd header_end - header_start ; header length
    ; checksum
    dd 0x100000000 - (0xe85250d6 + 0 + (header_end - header_start))

    ; required end tag
    dw 0    ; type
    dw 0    ; flags
    dd 8    ; size
header_end:

BITS 64

section .text

pagedir         equ  100000h

; these values come from qemu-lite
BOOT_GDT        equ  500h
BOOT_IDT        equ  520h
BOOT_PML4       equ 9000h

; Temp GDT and IDT
; TODO: to check this
gdtr:
  dw 8 * 4 - 1
  dd BOOT_GDT
idtr:
  dw 13ebh
  dd BOOT_IDT


; rsi points to zero_page structure
_multiboot_main:
  push rsi
  call paging
  ; Initialize CMOS shutdown code to 0ah
  mov al, 0fh
  out 070h, al
  mov al, 0ah
  out 071h, al
  ; When the signal INIT is sent, the execution starts in 2000h address 
  mov rsi , 2000h
  mov [rsi] , byte 0eah
  xor rax , rax
  ;mov eax , trampoline_init+boot32
  mov [rsi+1] , eax
  ; New page directory to handle 512GB
  mov rax , pagedir
  mov cr3 , rax
  ; jump to torokernel
  pop rsi
  kerneljump:
    jmp MULTIBOOT_MAIN

; Creates new page directory for handle 512 gb of memory
; we are using 2MB pages
; PML4( 512GB) ---> PDPE(1GB) --> PDE(2MB)
paging:
  mov rsi , pagedir
  pxor mm0 , mm0
  mov ecx , 262145
cleanpage:
  movq [rsi] , mm0
  add rsi , 8
  dec ecx
  jnz cleanpage

  ; first entry in PML4E table
  mov rsi , pagedir
  mov [rsi],dword pagedir + 4096 + 7

  ; next page is a PDPE
  mov rsi , pagedir + 4096
  mov rcx , pagedir + 7 + 4096 * 2
  ; Pointer page directory
  PPD:
   mov [rsi] , rcx
   add rsi , 8
   add rcx , 4096
   cmp rsi , pagedir + 4096 * 2
   jne PPD

  ; second page is PDE
  mov rsi , pagedir + 4096*2
  mov rcx , 7+128 ; the page is cacheable with writeback
  mov rax , 1 << 21
  PDE:
   mov [rsi] , rcx
   add rcx   , rax
   add rsi   , 8
   cmp rsi , pagedir +4096*514
   jne PDE
  ret

BITS 16
; This procedure is executed in SMP Initialization
; TODO: to use the idt, gdt and cr3 de multiboot
trampoline_init:
  ;lidt [idtr]
  ;lgdt [gdtr]
  ; Jump to protected mode
  mov ebx,cr0
  or  ebx, 1
  mov cr0,ebx
  ; Far jump 
  db 66h,0EAh
  dd trampoline_longmode
  dw 8h
; Code when jumping to Long Mode from other cores
trampoline_longmode:
  mov esp , 1000h
  ; Long mode initialization
  mov eax , cr4
  bts eax , 5
  mov cr4 , eax
  ;mov eax , BOOT_PML4
  mov cr3 , eax
  mov ecx, 0c0000080h
  rdmsr
  bts eax,8
  wrmsr
  mov eax,cr0
  bts eax,31
  mov cr0,eax
  ; Jump to kernel main
  ;db 066h
  ;db 0eah
  ; TODO:
  ;dd boot32+jumpkernel
  ;dw kernel_code64
