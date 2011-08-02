//
// Arch.pas
//
// Here are declared  functions and procedures for AMD x86-64 processors.
// The procedures are similar to i386 processor .
// It is independent of the other Units.
// It can be implement in others processors.
//
// Changes :
//
// 27/10/2009 Cache Managing Implementation
// 10/05/2009 SMP Initilization moved to Arch.pas . Supports Multicore.
// 09/05/2009 Size of memory calculated using INT15H .
// 12/10/2008 RelocateApic  is not used for the moment.
// 12/01/2006 RelocateApic procedure, QEMU does not support the relocation of APIC register
// 11/01/2006 Some modifications in Main procedure by Matias Vara .
// 28/12/2006 First version by Matias Vara .
//
// Copyright (c) 2003-2011 Matias Vara <matiasvara@yahoo.com>
// All Rights Reserved
//
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

unit Arch;

{$I Toro.inc}

interface

const
  // Exceptions Types
  EXC_DIVBYZERO = 0;
  EXC_OVERFLOW = 4;
  EXC_BOUND = 5;
  EXC_ILEGALINS = 6;
  EXC_DEVNOTAVA = 7;
  EXC_DF = 8;
  EXC_STACKFAULT = 12;
  EXC_GENERALP = 13;
  EXC_PAGEFAUL = 14;
  EXC_FPUE = 16;
 
  // Regions Memory Types
  MEM_AVAILABLE = 1;
  MEM_RESERVED = 2;

type
  TNow = record
    sec : LongInt;
    min: LongInt;
    hour: LongInt;
    day: LongInt;
    Month: LongInt;
    Year: LongInt
  end;
  PNow = ^TNow;

  TMemoryRegion = record
    Base: QWord;
    Length: QWord;
    Flag: Word; // MEM_RESERVED, MEM_AVAILABLE
  end;
  PMemoryRegion = ^TMemoryRegion;

  TCore = record
    Apicid: LongInt; // Core Identification
    Present: Boolean; // Is present?
    CPUBoot: Boolean;
    InitConfirmation: Boolean; // Syncronitation variable between core to INIT-core
    InitProc: procedure; // Procedure for Initialize the core
  end;

procedure bit_reset(val: Pointer; pos: QWord);
procedure bit_set ( addval : Pointer ; pos : QWord ) ;
function bit_test ( Val : Pointer ; pos : QWord ) : Boolean;
procedure change_sp (new_esp : Pointer ) ;
// only used in the debug unit to synchronize access to serial port
function cmpchg(cmpval, newval: DWORD; var addval: DWORD): DWORD;
procedure Delay(clock_hz: Int64; milisec: LongInt);
procedure eoi;
function GetApicID: Byte;
function get_irq_master: Byte;
function get_irq_slave: Byte;
procedure hlt;
procedure irq_on(irq: Byte);
procedure irq_off(irq: Byte);
function is_apic_ready: Boolean ;
function read_portb(port: Word): Byte;
function read_rdtsc: Int64;
procedure send_apic_init (apicid : Byte) ;
procedure send_apic_startup (apicid , vector : Byte );
procedure SwitchStack(sv: Pointer; ld: Pointer);
procedure write_portb(Data: Byte; Port: Word);
procedure CaptureInt (int: Byte; Handler: Pointer);
procedure CaptureException(Exception: Byte; Handler: Pointer);
procedure ArchInit;
procedure Now (Data: PNow);
procedure EnabledINT;
procedure DisabledINT;
procedure Interruption_Ignore;
procedure IRQ_Ignore;
function PciReadDWORD (bus, device, func, regnum : LongInt) : LongInt;
function GetMemoryRegion (ID: LongInt ; Buffer : PMemoryRegion): LongInt;
procedure InitCore(ApicID: Byte);
procedure SetPageCache(Add: Pointer);
procedure RemovePageCache(Add: Pointer);

const
  MP_START_ADD = $e0000; // we will start the search of mp_floating_point begin this address
  RESET_VECTOR = $467; // when the IPI occurs the procesor jumps here
  cpu_type = 0;
  apic_type = 2;
  MAX_CPU = 8;  // Number of max CPU support
  ALLOC_MEMORY_START = $800000; // Address Start of Alloc Memory
  KERNEL_IMAGE_START = $400000;
  PAGE_SIZE = 2*1024*1024; // 2 MB per Page
  HasCacheHandler: Boolean = True;
  HasException: Boolean = True;
  HasFloatingPointUnit : Boolean = True;

var
  CPU_COUNT: LongInt; // Number of CPUs detected while smp_init
  AvailableMemory: QWord; // Memory in the system
  LocalCpuSpeed: Integer;
  StartTime: TNow;
  CPU_CYLES: Int64;
  Cores: array[0..MAX_CPU-1] of TCore;

implementation

const
  Apic_Base = $Fee00000;
  apicid_reg = apic_base + $20 ;
  icrlo_reg = apic_base + $300 ;
  icrhi_reg = apic_base + $310 ;
  err_stat_reg = apic_base + $280 ;
  timer_reg = apic_base + $320 ;
  timer_init_reg = apic_base + $380 ;
  timer_curr_reg = apic_base + $390;
  divide_reg = apic_base + $3e0 ;
  eoi_reg = apic_base + $b0;
  
  // IDT descriptors
  gate_syst = $8E;
  
  // Address of Page Directory
  PDADD = $100000;
  IDTADDRESS = $3020;
	
  // 64bits selector
  Kernel_Code_Sel = $18;
  Kernel_Data_Sel = $10;

  // minimal stack for initialization process, in bytes
  size_start_stack = 700;

type 
  p_apicid_register = ^apicid_register ;
  apicid_register = record
    res : Word ;
    res0 : Byte ;
    apicid : Byte ;
  end;

  gdtr_struct = record
    limite: Word;
    res1, res2: DWORD;
  end;


  p_mp_floating_struct  = ^mp_floating_struct ;
  mp_floating_struct = record
    signature : array[0..3] of Char ;
    phys : DWORD ;
    data : DWORD;
    mp_type : DWORD ;
  end;

  p_mp_table_header = ^mp_table_header ;
  mp_table_header = record
    signature : array[0..3] of Char ;
    res : array[0..6] of DWORD ;
    size : Word ;
    count : Word ;
    addres_apic : DWORD;
    resd : DWORD ;
  end;

  p_mp_processor_entry = ^mp_processor_entry ;
  mp_processor_entry = record
    tipe: Byte ;
    apic_id: Byte ;
    apic_ver: Byte ;
    flags: Byte ;
    signature: DWORD ;
    feature: DWORD ;
    res: array[0..1] of DWORD ;
  end;

  p_mp_apic_entry = ^mp_apic_entry ;
  mp_apic_entry = record
    tipe : Byte ;
    apic_id : Byte ;
    apic_ver : Byte ;
    flags : Byte ;
    addres_apic : DWORD ;
  end;

  //  AMD X86-64  interrupt gate
  intr_gate_struct = record
    handler_0_15: Word;
    selector: Word;
    nu: Byte;
    tipe: Byte;
    handler_16_31: Word;
    handler_32_63: DWORD;
    res: DWORD;
  end;

  TInterruptGateArray = array[0..255] of intr_gate_struct;
  PInterruptGateArray = ^TInterruptGateArray;
  p_intr_gate_struct = ^intr_gate_struct;

  Pdirectory_page = ^directory_page_entry;

  directory_page_entry = record
    page_descriptor: QWord;
  end;

var
  idt_gates: PInterruptGateArray; // Pointer to IDT

// put interruption gate in the idt
procedure CaptureInt(int: Byte; Handler: Pointer);
begin
  idt_gates^[int].handler_0_15 := Word(QWord(handler) and $ffff) ;
  idt_gates^[int].selector := kernel_code_sel;
  idt_gates^[int].tipe := gate_syst ;
  idt_gates^[int].handler_16_31 := Word((QWord(handler) shr 16) and $ffff);
  idt_gates^[int].handler_32_63 := DWORD(QWord(handler) shr 32);
  idt_gates^[int].res := 0 ;
  idt_gates^[int].nu := 0 ;
end;	

procedure CaptureException(Exception: Byte; Handler: Pointer);
begin
  idt_gates^[Exception].handler_0_15 := Word(QWord(handler) and $ffff) ;
  idt_gates^[Exception].selector := kernel_code_sel;
  idt_gates^[Exception].tipe := gate_syst ;
  idt_gates^[Exception].handler_16_31 := Word((QWord(handler) shr 16) and $ffff);
  idt_gates^[Exception].handler_32_63 := DWORD(QWord(handler) shr 32);
  idt_gates^[Exception].res := 0 ;
  idt_gates^[Exception].nu := 0 ;
end;

procedure write_portb(Data: Byte; Port: Word); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov dx, port
  mov al, data
  out dx, al
end;

function read_portb(port: Word): Byte; assembler;{$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov dx, port
  in al, dx
end;


procedure write_portw (data: DWORD; port: Word); {$IFDEF ASMINLINE} inline; {$ENDIF}
var
  r : Pointer;
begin
  r :=@data;
  asm
    mov dx , port
    mov rsi, r
    outsw
  end;
end;

function read_portw(port: Word): Word;{$IFDEF ASMINLINE} inline; {$ENDIF}
var
	tmp: Word;
	P: Pointer;
begin
  P := @tmp;
  asm
	  mov dx, port
	  mov rdi, P
	  insw
  end;
  Result := tmp;
end;

procedure write_portd (data: DWORD; port: Word);{$IFDEF ASMINLINE} inline; {$ENDIF}
var
  r: Pointer;
begin
  r := @data;
  asm
    mov dx , port
	  mov rsi, r
	  outsd
  end;
end;

function read_portd (port: Word): DWORD; {$IFDEF ASMINLINE} inline; {$ENDIF}
var
  tmp: DWORD ;
  P: Pointer;
begin
  p := @tmp;
  asm
	  mov dx , port
	  mov rdi , p
	  insd
  end;
  Result := tmp;
end;

// Send init interrupt to apicid   .
// Use only in initialization procedure
procedure send_apic_init (apicid : Byte) ;
var
	icrl, icrh: ^DWORD;
begin
	icrl := Pointer(icrlo_reg);
	icrh := Pointer(icrhi_reg) ;
	icrh^ := apicid shl 24 ;
	// mode : init   , destination no shorthand
	icrl^ := $500;
end;


// Send the startup IPI for initialize for processor 
procedure send_apic_startup(apicid, vector: Byte);
var
  icrl, icrh: ^DWORD;
begin
  delay(LocalCpuSpeed,50);
  icrl := Pointer(icrlo_reg);
  icrh := Pointer(icrhi_reg) ;
  icrh^ := apicid shl 24 ;
  // mode : init   , destination no shorthand
  icrl^ := $600 or vector;
end;


// get Apicid of local apic 
function GetApicID: Byte;{$IFDEF ASMINLINE} inline; {$ENDIF}
var
  r: PDWORD;
begin
  r := Pointer(apicid_reg);
  result := r^ shr 24 ;
end;

// read the IPI delivery status
// check Delivery Status register
function is_apic_ready: Boolean;{$IFDEF ASMINLINE} inline; {$ENDIF}
var
  r: PDWORD;
begin
  r := Pointer(icrlo_reg) ;
  if (r^ and $1000) = 0 then
    Result := True
  else
    Result := False;
end;

// wait milisec using the clock bus speed in clock_hz 
// the apic interrupt need the clock_hz
procedure Delay(clock_hz: Int64; milisec: LongInt);
var
  tmp : ^DWORD ;
begin
  tmp := Pointer (divide_reg);
  tmp^ := $b;
  tmp := Pointer(timer_init_reg); // set the count
  tmp^ := (clock_hz div 1000)*milisec; // the count is aprox.
  tmp := Pointer (timer_curr_reg); // wait for the counter
  while tmp^ <> 0 do
  begin
    asm
      nop;
      nop;
      nop;
    end;
  end;
  // send the end of interruption
  tmp := Pointer(eoi_reg);
  tmp^ := 0;
end;

// Change the Address of Apic registers
procedure RelocateAPIC;
var
 reg:DWORD;
begin
  reg := Apic_Base;
  asm
    mov ecx, 27
    mov edx, 0
    mov eax, reg
    wrmsr
  end;
end;

// some local structure for irq
const
  Status_Port : array[0..1] of Byte = ($20,$A0);
  Mask_Port : array[0..1] of Byte = ($21,$A1);
  PIC_MASK: array [0..7] of Byte =(1,2,4,8,16,32,64,128);
  
// move the irq of 0-15 to 31-46 vectors
procedure RelocateIrqs ;
begin
asm
    mov   al , 00010001b
    out   20h, al
    nop
    nop
    nop
    out  0A0h, al
    nop
    nop
    nop
    mov   al , 20h
    out   21h, al
    nop
    nop
    nop
    mov   al , 28h
    out  0A1h, al
    nop
    nop
    nop
    mov   al , 00000100b
    out   21h, al
    nop
    nop
    nop
    mov   al , 2
    out  0A1h, al
    nop
    nop
    nop
    mov   al , 1
    out   21h, al
    nop
    nop
    nop
    out  0A1h, al
    nop
    nop
    nop

    mov   al , 0FFh
    out   21h, al
    mov   al , 0FFh
    out  0A1h, al
end;
end;

// hability the irq
procedure irq_on(irq: Byte);
begin
  if irq > 7 then
    write_portb(read_portb($a1) and (not pic_mask[irq-8]), $a1)
  else
    write_portb(read_portb($21) and (not pic_mask[irq]), $21);
end;

// turn off the irq
procedure irq_off(irq: Byte);
begin
  if irq > 7 then
    write_portb(read_portb($a1) or pic_mask[irq-8], $a1)
  else
    write_portb(read_portb($21) or pic_mask[irq], $21);
end;

// send the end of interruption to controllers
procedure eoi;
begin
  write_portb ($20, status_port[0]);
  write_portb ($20, status_port[1]);
end;

// turn off all irqs
procedure all_irq_off ;
begin
  write_portb($ff,mask_port[0]);
  write_portb($ff,mask_port[1]);
end;

// simple ,  get the number of irq of master controller 
function get_irq_master: Byte ;
begin
  write_portb ($b,$20);
  // some delay
  asm
    nop
    nop
    nop
  end;
  Result := read_portb($20);
end;

function get_irq_slave : Byte ;
begin
  write_portb ($b,$a0);
  // some delay
  asm
    nop
    nop
    nop
  end ;
  Result := read_portb($a0);
end;



// From this procedure never back
procedure RetOfInterruption; [nostackframe]; assembler;
asm
  pop r15 // IP of  INT Hanlder
  db $78 // Funcking IRET for AMD64!!!!!!!!!!!!
end;



const 
  cmos_port_reg = $70 ;
  cmos_port_rw  = $71 ;

// write a value of the cmos register
procedure cmos_write(data, reg: Byte);
begin
write_portb(reg , cmos_port_reg);
write_portb(data,cmos_port_rw);
end;

// read a value for cmos register 
function cmos_read (reg : Byte ): Byte;
begin
	write_portb (reg , cmos_port_reg);
	Result := read_portb(cmos_port_rw);
end;


// this code hes been extracted from DelphineOS <delphineos.sourceforge.net>
// return the CPU speed in MHZ
procedure CalculateCpuSpeed;
var
  count_lo, count_hi, family: DWORD;
  speed : Word ;
begin
asm
 mov eax , 1
 cpuid
 and eax , $0f00
 shr eax , 8
 mov family , eax
 
 in    al , 61h
 nop
 nop
 and   al , 0FEh      
 out   61h, al
 nop
 nop
 mov   al , 0B0h    
 out   43h, al  
 nop
 nop
 mov   al , 0FFh  
 out   42h, al   
 nop
 nop
 out   42h, al  
 nop
 nop
 in    al , 61h
 nop
 nop
 or    al , 1 
 out   61h, al

 rdtsc    
 add   eax, 3000000
 adc   edx, 0
 cmp   family, 6
 jb    @TIMER1
 add   eax, 3000000
 adc   edx, 0
@TIMER1:
  mov   count_lo, eax  
  mov   count_hi, edx

@TIMER2:
  rdtsc
  cmp   edx, count_hi   
  jb    @TIMER2
  cmp   eax, count_lo
  jb    @TIMER2        
 
  in    al , 61h
  nop
  nop
  and   al , 0FEh      
  out   61h, al  
  nop
  nop
  mov   al , 80h     
  out   43h, al
  nop
  nop
  in    al , 42h       
  nop
  nop
  mov   dl , al
  in    al , 42h        
  nop
  nop
  mov   dh , al        

  mov   cx , -1
  sub   cx , dx        
  xor   ax , ax
  xor   dx , dx
  cmp   cx , 110
  jb    @CPUS_SKP
  mov   ax , 11932
  mov   bx , 300
  cmp   family, 6
  jb    @TIMER3
  add   bx , 300
@TIMER3:
  mul   bx
  div   cx
  push  ax
  push  bx
  mov   ax , dx
  mov   bx , 10
  mul   bx
  div   cx
  mov   dx , ax
  pop   bx
  pop   ax
@CPUS_SKP:
  mov LocalCpuSpeed,  ax
  end ;
end;

// stop the executation of cpu 
procedure hlt ; assembler ; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  hlt
end;

// get the rdtsc counter 
function read_rdtsc: Int64;
var
  lw, hg: DWORD;
begin
  asm
    rdtsc
    mov lw, eax
    mov hg, edx
  end;
  Result := (hg shl 32) or lw ;
end;

// atomic compare and change 
function cmpchg(cmpval, newval: DWORD; var addval: DWORD): DWORD;assembler;inline;
asm
@spin:
  nop
  nop
  nop
  nop
  mov rax , cmpval
  mov rdx , newval
  mov rcx , addval
  lock cmpxchg [rcx] , rdx
jnz @spin
end;

// this procedures doesn't have lock protection
function bit_test (Val: Pointer; pos: QWord): Boolean;
var
	s: Byte;
begin
asm
  xor rax , rax
  xor rbx , rbx
  mov rbx , pos
  mov rsi , Val
  bt  [rsi] , rbx
  jc  @si
  @no:
   mov s , 0
   jmp @salir
  @si:
    mov s , 1
  @salir:
  end;
  Result := Boolean(s);
end;

procedure bit_reset(val: Pointer; pos: QWord); assembler;
asm
  mov rbx , pos
  mov rsi , val
  btr [rsi] , rbx
end;

procedure bit_set(addval: Pointer; pos: QWord); assembler;
asm
  mov rsi , addval
  xor rdx , rdx
  mov rdx , pos
  bts [rsi] , rdx
end;

procedure change_sp(new_esp: Pointer); assembler ;{$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  mov rsp, new_esp
  ret
end;

procedure SwitchStack(sv: Pointer; ld: Pointer); assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
	mov [sv] , rbp
	mov rbp , [ld]
end;

//------------------------------------------------------------------------------
// Memory Detection .From Int 15h information.
//------------------------------------------------------------------------------

type
  Int15h_info = record
    base   : QWord;
    length : QWord;
    tipe   : DWORD;
    res    : DWORD;
  end;
  PInt15h_info = ^Int15h_info;

const
  INT15H_TABLE = $30000;

var
  CounterID: LongInt; // starts with CounterID = 1

// Return information about a region of Memory
function GetMemoryRegion (ID: LongInt ; Buffer : PMemoryRegion): LongInt;
var
  desc: PInt15h_info;
begin
  if ID > CounterID then
    Result :=0
  else
    Result := SizeOf(TMemoryRegion);
  desc:= Pointer(INT15H_TABLE) + SizeOf(Int15h_info) * (ID-1);
  Buffer.Base := desc.Base;
  Buffer.length := desc.length;
  Buffer.Flag := desc.tipe;
end;


// Initialize Memory table  . It uses information from bootloader.
// The bootloader use INT15h.
// Usable memory is above 1MB
procedure MemoryCounterInit;
var
  magic: ^DWORD;
  desc: PInt15h_info;
begin
  CounterID:=0;
  AvailableMemory:=0;
  magic:= Pointer(INT15H_TABLE);
  desc:= Pointer(INT15H_TABLE);
  while magic^ <> $1234 do
  begin
    if (desc.tipe = 1) and (desc.Base >=$100000) then
      AvailableMemory:=AvailableMemory + desc.length;
    Inc(magic);
    Inc(desc);
  end;
  // Allocation start at ALLOC_MEMORY_START
  AvailableMemory := AvailableMemory;
  CounterID := (QWord(magic)-INT15H_TABLE);
  CounterID := counterId div SizeOf(Int15h_info);
end;

procedure Bcd_To_Bin(var val: LongInt); {$IFDEF ASMINLINE} inline; {$ENDIF}
begin
  val := (val and 15) + ((val shr 4) * 10 );
end;

// Now : Return the actual time from the CMOS .
procedure Now(Data: PNow);
var
  Sec, Min, Hour,
  Day, Mon, Year: LongInt;
begin
  repeat
    Sec  := Cmos_Read(0);
    Min  := Cmos_Read(2);
    Hour := Cmos_Read(4);
    Day  := Cmos_Read(7);
    Mon  := Cmos_Read(8);
    Year := Cmos_Read(9);
  until Sec = Cmos_Read(0);
  Bcd_To_Bin(Sec);
  Bcd_To_Bin(Min);
  Bcd_To_Bin(Hour);
  Bcd_To_Bin(Day);
  Bcd_To_Bin(Mon);
  Bcd_To_Bin(Year);
  Mon := Mon - 2 ;
  if 0 >= Mon then
  begin
    Mon := Mon + 12 ;
    Year := Year + 1;
  end;
  Data.sec := sec;
  Data.min := min;
  Data.hour := hour;
  Data.Month:= Mon;
  Data.day := Day;
  Data.Year := Year;
  Data.Year := Year;
end;

procedure nolose; [public, alias: 'FPC_ABSMASK_DOUBLE'];
begin
end;

procedure nolose2;[public, alias: 'FPC_EMPTYINTF'];
begin
end;

// simple procedures to manipulate interruptions
procedure EnabledINT; assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  sti
end;

procedure DisabledINT; assembler; {$IFDEF ASMINLINE} inline; {$ENDIF}
asm
  cli
end;


// Procedures for capture unhandles interruptions
procedure Interruption_Ignore;[nostackframe];
begin
  EnabledINT;
  asm
  db $48
  db $cf
  end;
end;

procedure IRQ_Ignore;[nostackframe];
begin
  EnabledINT;
  EOI;
  asm
  db $48
  db $cf
  end;
end;

//
// Access to PCI bus
//
const
 PCI_CONF_PORT_INDEX = $CF8;
 PCI_CONF_PORT_DATA  = $CFC;

function PciReadDWORD(bus, device, func, regnum : LongInt): LongInt;
var
  send: LongInt;
begin
  asm
    xor rax , rax
    xor rbx , rbx
    mov   eax, $80000000
    mov   ebx, bus
    shl   ebx, 16
    or    eax, ebx
    mov   ebx, device
    shl   ebx, 11
    or    eax, ebx
    mov   ebx, func
    shl   ebx, 8
    or    eax, ebx
    mov   ebx, regnum
    shl   ebx, 2
    or    eax, ebx
    mov   send, eax
  end;
  write_portd(send,PCI_CONF_PORT_INDEX);
  Result := read_portd(PCI_CONF_PORT_DATA);
end;


// Initilization of the SSE and SSE2 Extensions
// Every Core has got to do that
// TODO : Floating-Point exception is ignored
procedure SSEInit;assembler;
asm
  xor rax , rax
  // Set OSFXSR bit
  mov rax, cr4
  or ah , 10b
  mov cr4 , rax
  xor rax , rax
  mov rax , cr0
  // Clear MP and EM bit
  and al ,11111001b
  mov cr0 , rax
end;


//------------------------------------------------------------------------------
//                               Multicore Initilization
//------------------------------------------------------------------------------

var
  // temporary stacks for each cpu
  start_stack: array[0..MAX_CPU-1] of array[1..size_start_stack] of Byte;
  // Pointer to Stack for each CPU during SMP Initilization
  esp_tmp: Pointer;

// External Declarations for Initialization
procedure KernelStart; external name 'KernelStart';
procedure boot_confirmation; forward;

// Start stack for Initialization of CPU#0
var
 stack : array[1..5000] of Byte ;

const
 pstack : Pointer = @stack[5000] ;

// Initialize the CPU in SMP initialization
procedure InitCpu; assembler;
asm
  mov rax, Kernel_Data_Sel
  mov ss, ax
  mov es, ax
  mov ds, ax
  mov gs, ax
  mov fs, ax
  mov rsp, esp_tmp
  // load new Page Directory
  mov rax, PDADD
  mov cr3, rax
  xor rbp, rbp
  sti
  call SSEInit
  call boot_confirmation
end;

// entry point of PE64 executable
procedure main; [public, alias: '_mainCRTStartup']; assembler;
asm
  mov rax, cr3 // Cannot remove this warning! using eax generates error at compile-time.
  cmp rax, 90000h
  je InitCpu
  mov rsp, pstack
  xor rbp, rbp
  call KernelStart
end;

// Boot CPU using IPI messages.
// Warning this procedure must be do it just one per CPU
procedure InitCore(ApicID: Byte);
var
  Attempt: LongInt;
begin
  Attempt := 2;
  while Attempt > 0 do
  begin
    // wakeup the remote core with IPI-INIT
    send_apic_init(apicid);
    Delay(CPU_CYLES, 50);
    // send the first startup
    send_apic_startup(ApicID, 2);
    Delay(CPU_CYLES  ,50);
    // remote CPU read the IPI?
    if not is_apic_ready then
    begin // some problem ?? wait for 2 sec
      Delay(CPU_CYLES, 200);
      if not is_apic_ready then
        Exit; // Serious problem -> exit
    end;
    send_apic_startup(ApicID, 2);
    Delay(CPU_CYLES, 50);
    Dec(Attempt);
  end;
  esp_tmp := Pointer(esp_tmp) - size_start_stack;
end;

// Simple syncronization with bsp CPU
procedure boot_confirmation;
var
  CpuID: Byte;
begin
  CpuID := GetApicID;
  Cores[CPUID].InitConfirmation := True;
  // Local Kernel Initilization
  Cores[CPUID].InitProc;
end;

// detect APICs on MP table
procedure mp_apic_detect(table: p_mp_table_header);
var
  m: ^Byte;
  I: LongInt;
  tmp: Pointer;
  cp: p_mp_processor_entry ;
begin
  m := Pointer(SizeUInt(table) + SizeOf(mp_table_header));
  I := 0;
  while I < table.count do
  begin
    if (m^  = cpu_type) and (CPU_COUNT < MAX_CPU-1) then
    begin
    // I must do ^Byte > Pointer > p_mp_processor_entry
      tmp := m;
      cp := tmp;
      CPU_COUNT:=CPU_COUNT+1;
      Cores[cp.Apic_id].Apicid := cp.Apic_id;
      Cores[cp.Apic_id].present := True;
      m := m+SizeOf(mp_processor_entry);
      // Boot core doesn't need initilization
      if (cp.flags and 2 ) = 2 then
        Cores[cp.Apic_id].CpuBoot := True ;
    end else
    begin
      m := m+SizeOf(mp_apic_entry);
    end;
    Inc(I);
  end;
end;


// search and read the Mp configuration table version 1.4  , the begin of search is in $e000 address
procedure mp_table_detect;
var
  find: p_mp_floating_struct;
begin
  find := Pointer(MP_START_ADD) ;
  while SizeUInt(find) < $fffff do
  begin
    if (find.signature[0]='_') and (find.signature[1]='M') then
    begin
      if SizeUInt(find.phys) <> 0 then
      begin
        mp_apic_detect(Pointer(SizeUint(find.phys)));
        Exit;
      end
      else exit;
    end;
    find := find+1;
   end;
end;


//
// Structures of ACPI table.
//

type
  TAcpiRsdp = packed record
    Signature: array[0..7] of Char;
    Checksum: Byte;
    oem_id:array[0..5] of Byte;
    Revision: Byte;
    rsdt_address: DWORD;
    Length: DWORD;
    xsdt_address: QWord;
    ext_checksum: Byte;
    Reserved: array[0..2] of Byte;
  end;
  PAcpiRsdp = ^TAcpiRsdp;

  TAcpiTableHeader = packed record
    Signature: array[0..3] of Char;
    Length: DWORD;
    Revision: Byte;
    Checksum: Byte;
    oem_id: array[0..5] of Char;
    oem_table_id : array[0..7] of Char;
    oem_revision: DWORD;
    asl_compiler_id:array[0..3] of Char;
    asl_compiler_revision: DWORD;
  end;
  PAcpiTableHeader = ^TAcpiTableHeader;

  TAcpiRstd = packed record
    Header: TAcpiTableHeader;
    Entry: array[0..8] of DWORD;
  end;
  PAcpiRstd = ^TAcpiRstd;

  TAcpiMadt = packed record
    Header: TAcpiTableHeader;
    ApicAddr: DWORD;
    Res: DWORD;
  end;
  PAcpiMadt = ^TAcpiMadt;

  TAcpiMadtEntry = packed record
    nType: Byte;
    Length: Byte;
  end;
  PAcpiMadtEntry = ^TAcpiMadtEntry;

  TAcpiMadtProcessor = packed record
    Header: TAcpiMadtEntry;
    AcpiId: Byte;
    ApicId: Byte;
    Flags: DWORD;
  end;
  PAcpiMadtProcessor = ^TAcpiMadtProcessor;

// search and read the ACPI table
procedure acpi_table_detect;
var
  Counter, J: LongInt;
  Entry: PAcpiMadtEntry;
  madt: PAcpiMadt;
  MadEnd: Pointer;
  P: PChar;
  Processor: PAcpiMadtProcessor;
  RSDP: PAcpiRsdp;
  RSTD: PAcpiRstd;
  TableHeader: PAcpiTableHeader;
begin
  P := Pointer($e0000);
  while p < Pointer($100000) do
  begin
    // looking for RSD sign
    if (p[0] = 'R') and (p[1]='S') and (p[2]='D') then
    begin
      RSDP :=  Pointer(p);
      // maybe some sing detection on RSTD
      RSTD := Pointer(QWord(RSDP.rsdt_address));
      // number of entries in table
      Counter:= (RSTD.Header.Length - SizeOf(TAcpiTableHeader)) div 4;
      for J := 0 to Counter-1 do
      begin
        TableHeader := Pointer(QWord(RSTD.Entry[j])); // table header
        // "APIC" signature
        if (TableHeader.Signature[0] = 'A') and (TableHeader.Signature[1] = 'P')  then
        begin
          madt := Pointer(TableHeader);
          MadEnd := Pointer(madt) + TableHeader.length;
          Entry := Pointer(madt) + SizeOf(TAcpiMadt);
          while Entry < MadEnd do
          begin // that 's a new Processor.
            if Entry.nType=0 then
            begin
              Processor := Pointer(Entry);
              // Is Processor Enabled ??
              if Processor.flags and 1 = 1 then
              begin
                Inc(CPU_COUNT);
                Cores[Processor.apicid].Apicid := Processor.apicid;
                Cores[Processor.apicid].Present := True;
                // CPU#0 is a BOOT cpu
                if Processor.apicid = 0 then
                  Cores[Processor.apicid].CPUBoot := True;
              end;
            end;
            Entry := Pointer(Entry) + Entry.Length;
          end;
        end;
      end;
      Break;
    end;
    Inc(p, 16);
  end;
end;

// Detect all Cores using MP's Intel tables and ACPI Tables.
procedure SMPInitilization;
var
  J: LongInt;
begin
  // clear the tables
  for J :=0 to MAX_CPU-1 do
  begin
    Cores[J].present := False;
    Cores[J].CPUBoot:= False;
    Cores[J].Apicid := 0;
    Cores[J].InitConfirmation := False;
    Cores[J].InitProc := nil;
  end;
  CPU_COUNT := 0;
  acpi_table_detect; // ACPI detection
  if CPU_COUNT = 0 then
    mp_table_detect; // if cpu_count is zero then use a MP Tables
  // we have only one core
  if CPU_COUNT = 0 then
  begin
    CPU_COUNT:=1;
    // all this information is not important in this context
    Cores[0].present := True;
    Cores[0].CPUBoot := True;
    Cores[0].Apicid := GetApicid;
    Cores[0].InitConfirmation := True;
  end;
  // temporary stack used for initialization of every Core
  esp_tmp := @start_stack[MAX_CPU-1][size_start_stack];
end;


//
// Pagination and Cache's Manager
//

var
  PML4_Table:Pdirectory_page;

// We have to refresh the TLB's Cache
procedure FlushCr3;assembler;
asm
  mov rax, PDADD
  mov cr3, rax
end;

// Set Page as cacheable
// Add is Pointer to page , It's a multiple of 2MB (Page Size)
// Warning : Refresh TLB after use it
procedure SetPageCache(Add: Pointer);
var
  I_PML4,I_PPD,I_PDE: LongInt;
  PDD_Table, PDE_Table, Entry: Pdirectory_page;
  Page: QWord;
begin
  Page := QWord(Add);
  I_PML4:= Page div 512*1024*1024*1024;
  I_PPD := (Page div (1024*1024*1024)) mod 512;
  I_PDE := (Page div (1024*1024*2)) mod 512;
  Entry:= Pointer(PML4_Table + SizeOf(directory_page_entry)*I_PML4);
  PDD_Table := Pointer((entry.page_descriptor shr 12)*4096);
  Entry := Pointer(PDD_Table + SizeOf(directory_page_entry)*I_PPD);
  PDE_Table := Pointer((Entry.page_descriptor shr 12)*4096);
  // 2 MB page's entry
  Entry := Pointer(PDE_Table + SizeOf(directory_page_entry)*I_PDE);
  // PCD bit is Reset --> Page In Cached
  Bit_Reset(Pointer(PDE_Table + SizeOf(directory_page_entry)*I_PDE),4);
end;

// Set Page as not-cacheable
// Add is Pointer to page , It's a multiple of 2MB (Page Size)
// Warning : Refresh TLB after use it
procedure RemovePageCache(Add: Pointer);
var
  I_PML4,I_PPD,I_PDE: LongInt;
  PDD_Table, PDE_Table, entry: Pdirectory_page;
  page: QWord;
begin
  page:= QWord(Add);
  I_PML4:= Page div 512*1024*1024*1024;
  I_PPD := (Page div (1024*1024*1024)) mod 512;
  I_PDE := (Page div (1024*1024*2)) mod 512;
  entry:= Pointer(PML4_Table + SizeOf(directory_page_entry)*I_PML4);
  PDD_Table := Pointer((entry.page_descriptor shr 12)*4096);
  entry := Pointer(PDD_Table + SizeOf(directory_page_entry)*I_PPD);
  PDE_Table := Pointer((entry.page_descriptor shr 12)*4096);
  // 2 MB page's entry
  entry := Pointer(PDE_Table + SizeOf(directory_page_entry)*I_PDE);
  // PCD bit is Reset --> Page In Cached
  Bit_Set(Pointer(PDE_Table + SizeOf(directory_page_entry)*I_PDE),4);
end;

// Cache Manager Initialization
procedure CacheManagerInit;
var
  Page: Pointer;
begin
  Page := nil;
  PML4_Table := Pointer(PDADD);
  // First two Pages aren't Cacheable (0-2*PAGE_SIZE)
  // maybe we have ROM-BIOS and other Devices' Memory
  RemovePageCache(Page);
  Page := Page + PAGE_SIZE;
  RemovePageCache(Page);
  Page := Page + PAGE_SIZE;
  // The whole kernel is cacheable from bootloader
  FlushCr3;
end;

// Initialization of variables about the Architecture
procedure ArchInit;
var
  I: LongInt;
begin
  // the bootloader creates the idt
  idt_gates := Pointer(IDTADDRESS);
  FillChar(PChar(IDTADDRESS)^, SizeOf(intr_gate_struct)*256, 0);
  RelocateIrqs;
  MemoryCounterInit;
  // Cache Page structures
  CacheManagerInit;
  CalculateCpuSpeed;
  // increment of RDTSC counter per miliseg
  CPU_CYLES  := LocalCpuSpeed * 100000;
  Irq_On(2);
  // Hardware Interruptions
  for I := 33 to 47 do
    CaptureInt(I, @IRQ_Ignore);
  // CPU Exceptions
  for I := 0 to 32 do
    CaptureInt(I, @Interruption_Ignore);
  EnabledINT;
  Now(@StartTime);
  SMPInitilization;
  // Initilization of Floating Point Unit
  SSEInit;
end;


end.
