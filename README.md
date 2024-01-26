dragon-rom-and-floppy-emulator
==============================

Also now works on the Tandy Color Computer (tested on a Coco 2, but probably works on Coco 1 as well). 

More info at  https://www.kernelcrash.com/blog/emulating-roms-and-floppy-disks-on-the-dragon-32/

Heavily based on msx-rom-and-floppy-emulator (https://www.kernelcrash.com/blog/emulating-roms-and-floppy-drives-in-msx/)

Note the 'Wiring it' section below if you've built the earlier version. There are some changes.

Overview
--------
- Emulates ROMs and floppy disks for the Dragon 32 and Tandy Color Computer 2 (and possibly Dragon 64 and other similar machines)
  Both the Dragon and Tandy machines are very very similar at a technical level, and there are only minor differences when it comes to
  floppy interfacing.
- Take a cheap STM32F407 board (US$10 or so 'before the chip shortage'). Wire it into the dragon/tandy cartridge slot..
- Make a FAT32 partition on a micro SD card and put rom and dsk/vdk disk images on it.
- Plug the micro SD into the STM32F4 board.
- The STM32F4 board presents a rom image in real time to the Dragon or Tandy computer such that it thinks a rom cartridge is attached.
- It can also emulate a WD2797 floppy disk controller such that you can load disk images off the SD card. It will emulate
  a Dragon DOS (or other DOS) ROM cart at the same time.


Wiring it
---------

Using a STM32F407VET6 or STM32F407VGT6 board
```
   PA2         - wire a button between it and GND. No need for a pullup. This is 'NEXT'
   PA3         - wire a button between it and GND. No need for a pullup. This is 'PREV'
   PA4         - wire to a two pin jumper. Wire the other pin to GND. No need for a pullup. When you 
                 set the jumper to tie PA4 to GND it means the board is in Tandy Coco mode. When 
                 you don't have a jumper in place to GND it means the board is in Dragon 32 mode.

   PE0 to PE15 - A0 to A15
   PD8 to PD15 - D0 to D7

   PB6         - connects to PC4
   PB7         - E (p6) (see further down. _E connects to both PC0 and PB7)

   PC0         - E (p6)
   PC1         - _CTS (p32) (the cartridge chip select)
   PC2         - _P2 (p36)  (the $FF40-$FF5F chip select)

   PC3         - R/_W (p18)
   PC4         - PB6

   PC5         - _RESET

   PC6         - CART (PIA1 CB1) (note: CART is connected to Q for a real cartridge)
   PC7         - _NMI

   PC13        - _HALT (only required for Tandy mode)

   GND         - GND
```
Looking at the cartridge socket (pin 1 and 2 are towards the rear of the computer)
```
       1  +12V           2  +12V
       3  !HALT - PC13   4  !NMI - PC7
       5  !RESET - PC5   6  E (main clock) - PC0 & PB7
       7  Q (leads E)    8  CART (PIA1 CB1) - PC6
       9  +5V           10  D0 - PD8
      11  D1  - PD9     12  D2 - PD10
      13  D3  - PD11    14  D4 - PD12
      15  D5  - PD13    16  D6 - PD14
      17  D7  - PD15    18  R/!W - PC3
      19  A0  - PE0     20  A1 - PE1
      21  A2  - PE2     22  A3 - PE3
      23  A4  - PE4     24  A5 - PE5
      25  A6  - PE6     26  A7 - PE7
      27  A8  - PE8     28  A9 - PE9
      29  A10 - PE10    30  A11 - PE11
      31  A12 - PE12    32  !CTS ($C000-$FFEF) - PC1
      33  Ground        34  Ground
      35  Ext sound src 36  !P2 (PIA2 $FF40-$FF5F) - PC2
      37  A13 - PE13    38  A14 - PE14
      39  A15 - PE15    40  !DSD (Device Select Disable)
```
If you get a board with a microSD card slot, then the 'standard' wiring of the SD adapter
is fine.

The  DEVEBOX stm32f407 board I used during development has an LED attached to PA1, so various errors will result in PA1 flashing.

Setting up the micro SD card and using it
-----------------------------------------

I tend to format a micro SD card with a smallish partition (less than 1GB) with 
FAT32. If the board is in Dragon mode then you need:

  - A directory called 'dragon' containing .rom and .vdk files
  - a file called dragondos.rom in the root of the SD card. It will be 
    Dragon DOS 1.0 or SuperDOS

If the board is in Tandy mode:

  - A directory called 'tandy' containing .rom and .dsk files
  - a file called tandydos.rom in the root of the SD card. It will be 
    RS-DOS 1.1 or similar

The order in which you copy files into the dragon or tandy directories is 
the order they will appear when you are cycling through disks or roms (ie.
its not alphabetical).

If you then plugged the stm32f4 board in as described, then the Dragon or Coco
will look at the first file in the dragon or tandy directory and 'present' it.
If that file is a .rom file then the computer will see that as a cartridge at
0xC000. If its a .vdk or .dsk file then the appropriate DOS rom is loaded as a
cartridge at 0xC000 and you boot into BASIC. If you type DIR then you should see
a directory listing of that first .vdk or .dsk file.

Assuming you have presented a disk, if you press NEXT, then do a DIR again
(or power off/on the Dragon) then you should get a directory listing of the 2nd
disk you copied to the dragon directory and so on. PREV can be used to go to the
previous disk image.

It's not a bad idea to power the stm32f4 board separately so you can power off/on
the dragon when necessary without resetting the stm32f4 board to its first disk 
image (ie. make sure GND is connected from the Dragon to the stm32f4 board, but
leave +5V disconnected). Given that you can intermix .rom and disk image files 
in the dragon or tandy directory you can end up swapping out the DOS rom to 
replace with a different ROM. Chances are you would crash the computer at that
point. ie. it's best to power off/on the Dragon/Coco.

There is also a special ROM called menu.rom. If you have built it using lwtools
(see the build.sh script), you can copy menu.rom to the root of the SD card as
well. If you power off your Dragon or Coco, and reset the stm32f4 board, the Dragon
or Coco should now load the menu.rom at 0xC000 and show a disk/rom menuing system
called KCDFS (or renamed to KCCFS if you set the jumper for Tandy mode).
From the menu you can select a disk image or ROM and the Dragon or Coco will then boot
into what you selected (ie. if you chose a rom it will boot that ROM. If you
chose a disk, it will boot into BASIC with a DOS loaded and the disk image
in the first drive)

With the KCDFS/KCCFS menu.rom, the NEXT and PREV keys still operate as they should. So if 
say you had a disk image for a game. And the next disk was a blank disk you used
for game saves, then you just press NEXT when the game asks to save, and press
PREV to get back to the game disk. It only emulates one disk drive.

Normally to get back to the menu.rom you need to power down the Dragon or Coco and
also make sure the stm32f4 board is reset. However, there is a magic restart mode
whereby if you hold in the reset button of the Dragon or Tandy and then press the 
NEXT button, wait a second, then press the PREV button, then let go of the reset button
it will hopefully go back to the menu.rom. This won't work 100% of the time due to 
the way some games or software have been written. In that case you'll need to power
down the Dragon or Coco.

Copying the firmware to the stm32f407 board
-------------------------------------------

There are lots of options for writing firmware with the stm32 chips. There is 
an example of using dfu-util in the transfer.sh script. In order for this to 
work you would need to set the BOOT0 and or BOOT1 settings such that plugging
the board in via usb will show a DFU device. Then you can run transfer.sh. Remove
the BOOT0 or BOOT1 jumpers after you do this.

KCDFS/KCCFS
-----------

In the kcdfs directory is menu.s. It's a 6809 assembly program for the 
Dragon or Coco that can communicate to the stm32f4 board in order to show a list of all the 
files in the dragon directory of the SD card. You need lwtools to assemble it
into menu.rom that you need to put in the root of the SD card.

After reset of the stm32f4 board it should load menu.rom and present it.
So if you want to 'get back to the kcdfs menu', you can power down the
Dragon or Coco and hit reset on the stm32f4 board, then power on the Dragon. Sometimes
you can get away with just holding in the reset button of the Dragon, then tap
reset on the stm32f4 board, then let go of the Dragon reset button.

kcdfs is about as simple as I could go. No fancy graphics. On boot it
shows the first 12 or so files in the dragon directory of the SD card. They
are listed with 'A' to 'L' down the left hand side. You press a letter and your
Dragon should reboot and start up what you selected. Assuming there are 
more than 12 files in the dragon directory, you just press '2' for the 2nd
page of 12 files, '3' for the 3rd and so on. You can also press '?' to get
some help.

There is an ultra simple protocol used;

 - kcdfs reads 0xff50. Bit 6 reflects the Tandy/Dragon jumper setting on 
   the stm32f4 board. A 0 means Tandy mode. A 1 means Dragon mode.

 - kcdfs writes an 0x80 to 0xff50. That triggers the main thread of the 
   smt32f4 board to do a directory listing of the dragon or tandy directory.
   The stm32f4 board will write this directory listing into its own 
   memory in a series of 128 byte filename chunks.

 - kcdfs polls 0xff50 to see when bit 7 goes low. That means the file listing
   process has completed. The number of files retrieved is written to 0xff52.
   It can't be more than 126 or so, so its always a byte length

 - the list of filenames in the dragon directory is accessed by a paging
   mechanism. 0xff54 and 0xff55 are an address register into the stm32f4's
   memory where the filenames are stored in 128 byte chunks. The first 
   filename is at offset 0x0100, the 2nd at 0x0180 and so on. So the Dragon
   just needs to write 0x0100 to the 0xff54/0xff55 address register, then
   start to read the bytes of the filename from 0xff56. There is a built in
   autoincrement function , so the Dragon can just continue to read from 0xff56
   until it gets a 0x00 byte to signify the end of the filename.
   The Dragon would then write a 0x0180 to the 0xff54/0xff55 address register
   and would start to read the 2nd filename and so on. I will note too, that 
   unlike the 6809, the address register is little-endian. ie. the low byte
   goes to 0xff54, the high byte to 0xff55

 - kcdfs lets a user select a file. The filename is then copied in to the 
   0x0000 offset of the stm32f4. ie. the Dragon writes a 0x0000 to the 
   0xff54/0xff55 address register and then 'writes' the filename one byte
   at a time to 0xff55 including the trailing 0x00 byte.

   Then an 0x40 is written to 0xff50. That triggers the 
   main thread of the stm32f4 board to load the appropriate rom or disk.
   As soon as the 0x40 is written, the code triggers a cold reset of the dragon
   computer. 

__Summary__
```
0xff50        - command register
0xff51        - spare
0xff52/0xff53 - number of files returned in a directory listing. In little endian (so 0xff52 is the low byte)
0xff54/0xff55 - address register into a directory buffer
0xff56        - byte to read from the directory buffer OR byte to write to the directory buffer
```

Technical
--------------------------

When E goes low (-ve edge) it triggers TIM4 (PB7) to generate a one-pulse in 190
or so nanoseconds. The one-pulse comes out of PB6. PB6 is connected to PC4 to
generate an EXTI4 interrupt. What this all means is that the first line of the 
EXTI4 interrupt handler is often executed 290ns or so from the fall of E. That may
seem silly as generally E is low for about 550ns when the 6809E is clocked at 
0.9MHz. But if a program uses 'the speed poke', then E is potentially low for
half the time (ie. 280-ish ns). Either way, at the start of the EXTI4 interrupt
handler, we wait for E to be high.

So now E has gone high, we can read the address bus to see 

 - Is it a ROM read?
 - Is it a P2 peripheral access?

ROMs are accessed at 0xc000 to 0xffef with some holes along the way. The !CTS pin
goes low , so its easy to tell its a ROM access. As soon as this is detected it's
a mad dash to look at the address bus of the 6809, then grab the appropriate byte
from a ROM that was already preloaded into the stm32f4's RAM earlier, then change 
the databus such that the stm32f4 can output the byte, then  wait for E to go low.
And as soon as it goes low tri-state the databus bins and exit the interrupt routine.

The P2 peripheral access is different depending if we are in Dragon or Tandy mode

 - - The Dragon has a WD2793 or similar at 0xff40 to 0xff43, and a related latch at 0xff48
   - The Tandy has a similar FDC at 0xff48 to 0xff4b, and it's related latch at 0xff40

Regardless of the mapping, the FDC and latch are emulated.

A key difference between this and the previous floppy emulation stuff I've done is 
that the Dragon and Tandy use interrupts. It varies a bit between the Dragon and
Tandy though

- In the Dragon the DRQ from the FDC goes to the CART cartridge pin
which is an edge trigger on one of the 6821s. And the INTRQ goes through some gates
to NMI on the 6809. Essentially bit 5 of that latch at 0xff48 can mask or unmask the
INTRQ. If the latch has bit 5 high then a high on INTRQ will drive NMI low causing
an NMI interrupt.

- In the Tandy the INTRQ pin on the FDC is gated to connect to _NMI. It actually uses
the DENSITY bit of the latch to do this. When DENSITY is high, _NMI can go low
when INTRQ goes high. For DRQ, it is gated by bit 7 of the latch such that
_HALT will go low only when DRQ is low and bit 7 of the latch are high.  That means
that _HALT will go low at the end of a DRQ rather than the beginning. There is
additional logic that says when INTRQ goes low that bit 7 of the latch 
will be forced low. So when INTRQ ends, _HALT must end up going high.

This interrupt stuff ended up quite interesting as you need to delay it a bit. Initially
this caused the branch that worked on the Dragon to be quite different to the one that
worked with the Tandy ... and this paragraph does not do justice to how long it took
to try to combine the two branches so the code base worked OK on both computers ;-)

Much of the code is a lift/shift of the msx-rom-and-floppy-emulator, so have a read 
of that if you are interested in the use of FPU registers and WFE stuff.

VDK disk files are effectively loading a track at a time into the STM32F4's RAM during
a WD2793 SEEK command. Requests to read or write sectors are effectively just reading
or writing into this track buffer. That should be fast, but as mentioned it has to 
be slowed down a fair bit to keep the 6809E happy.

VDK files that I've used seem to mostly be single sided, 40 track, with 18 sectors
of 256 bytes per track. The emulation assumes this sort of structure. 

The read and write sector WD2793 commands are implemented, but the read/write track
stuff is not. So that means it should work with most stuff, but don't try formatting
anything.

I've tested it with Dragon Dos 1.0 and 1.2 as well as SuperDOS E6. They seem to work.

I have tested the Tandy side with RS-DOS 1.1 (disk11.rom).

Note also that the _RESET signal of the Dragon is monitored. After the stm32f4 board
resets it makes sure the _RESET on the Dragon is high for a while to indicate that it
should be out of reset. The rationale is that before _RESET is stable at a high level
there is potentially a lot of erratic activity that could stuff up the EXTI interrupt
processing.

I found most Coco software is in DSK format which is just a raw dump of the 35 
tracks of 18x256 sectors. ie. filesize of 161280 bytes. For me this just means there
is no header anymore (which VDK files have).


About OS-9 and Nitros-9
--------------------------------------------
OS-9 and Nitros-9 for a Coco 2 with 64K should just work fine. Basically insert the disk, 
type DOS and you should see 'OS9 BOOT' or 'NITROS9 BOOT' and eventually the main OS-9 screen
and a prompt.

So OS-9 on Dragon does work. However OS-9 was designed for the Dragon 64
in the Dragon world. My Dragon 32 has had the 64K mod done to it and OS-9 does sort
of work on it. Per this page http://archive.worldofdragon.org/index.php?title=Dragon_32_-_64K_Upgrade
The OS-9 boot will hang due to the 6551 ACIA missing in a Dragon 32. So the 
basic deal for a modded Dragon 32 is

 - Insert the OS-9 disk for Dragon 64
 - Type BOOT
 - You should see 'OS9 BOOT' on the screen. 
 - Wait a few seconds
 - Press the reset button and you are back at the BASIC prompt. Enter

   POKE &HFF03,&H34:EXEC 9736

 - And you should see 'OS9 BOOT' on the screen again. Just wait a few seconds and
   you should see the main OS-9 screen and eventually a prompt.

I did look in to virtualising the ACIA, but the problem is that the primary PIA in a 
Dragon 32 is from FF00 to FF07, whereas in a Dragon 64 its from FF00 to FF03 with 
the ACIA from FF04 to FF07. You would need to at least cut the CS0/CS1 signals of the
primary PIA and then have an inverter between the CPU A2 and the CS0/CS1 signals. 
That would just lock the primary PIA to FF00 to FF03. Then I would need to write 
some code to send back some appropriate dummy values when FF04 to FF07 is read.

NitrOS-9 will work on the Dragon as well. In my case, none of the publicly 
downloadable images work with a 'Dragon 32 upgraded to 64K'. You will need to edit
level1/d64/makefile and set UPGRADED32 = 1 , then compile to generate new dsk images.

Thanks
------

I will note too that the xroar emulator and it's source was extremely helpful for
figuring out the interactions with the FDC (http://www.6809.org.uk/xroar/), even
though the floppy chip emulation code is still based mostly on fMSX.

Also the source code for Dragon DOS was enormously helpful too.
https://github.com/prime6809/DragonDOS



