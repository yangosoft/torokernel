//
// Toro Hello World Example.
//
// Clasical example using a minimal kernel to print "Hello World".
//
// Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
// All Rights Reserved
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

program ToroHello;

{$IFDEF FPC}
 {$mode delphi}
{$ENDIF}

{%RunCommand qemu-system-x86_64 -m 512 -smp 2 -drive format=raw,file=ToroHello.img}
{%RunFlags BUILD-}



// They are declared just the necessary units
// The needed units depend on the hardware where you are running the application
uses
  Kernel in '..\rtl\Kernel.pas',
  Process in '..\rtl\Process.pas',
  Memory in '..\rtl\Memory.pas',
  Debug in '..\rtl\Debug.pas',
  Arch in '..\rtl\Arch.pas',
  Filesystem in '..\rtl\Filesystem.pas',
  Pci in '..\rtl\drivers\Pci.pas',
  Console in '..\rtl\drivers\Console.pas';


    
{$L hello.o} 
Procedure _printDecimalFromC (); cdecl; external name 'printDecimal';

    
{$L hello.o} 
Function Hello(): Integer; cdecl; external name 'hello';  
var ret : Integer;
begin  
     WriteConsoleF('/RHello World, I am TORO !!!\n',[]);
     ret := hello();
     WriteConsoleF('/RThis value is from C: %d\n',[ret]);
     _printDecimalFromC();
     WriteConsoleF('/R <-- this comes from C calling a TORO API\n',[]);
     
     While True do hlt;
end.

