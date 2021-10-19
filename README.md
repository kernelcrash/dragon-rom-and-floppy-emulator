dragon-rom-and-floppy-emulator
==============================

More info at  https://www.kernelcrash.com/blog/emulating-roms-and-floppy-disks-on-the-dragon-32/

Heavily based on msx-rom-and-floppy-emulator (https://www.kernelcrash.com/blog/emulating-roms-and-floppy-drives-in-msx/)

Overview
--------

- Emulates ROMs and floppy disks for the Dragon 32 (and possibly Dragon 64 and other similar machines)
- Take a cheap STM32F407 board (US$10 or so 'before the chip shortage'). Wire it into the dragon cartridge slot..
- Make a FAT32 partition on a micro SD card and put rom and vdk disk images on it.
- Plug the micro SD into the STM32F4 board.
- The STM32F4 board presents a rom image in real time to the Dragon computer such that it thinks a rom cartridge is attached.
- It can also emulate a WD2797 floppy disk controller such that you can load disk images off the SD card. It will emulate
  a Dragon DOS (or other DOS) ROM cart at the same time.

Wiring it
---------

Using a STM32F407VET6 or STM32F407VGT6 board
```
   PA2         - wire a button between it and GND. No need for a pullup. This is 'NEXT'
   PA3         - wire a button between it and GND. No need for a pullup. This is 'PREV'

   PE0 to PE15 - A0 to A15
   PD8 to PD15 - D0 to D7

   PC0         - _E (p6)
   PC1         - _CTS (p32) (the cartridge chip select)
   PC2         - _P2 (p36)  (the $FF40-$FF5F chip select)

   PC3         - R/_W (p18)
   PC4         - unused

   PC5         - _RESET

   PC6         - CART (PIA1 CB1) (note: CART is connected to Q for a real cartridge)
   PC7         - _NMI

   GND         - GND
```
Looking at the cartridge socket
```
       1  +12V           2  +12V
       3  !HALT          4  !NMI - PC7
       5  !RESET (PC5)   6  E (main clock) - PC0
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
If you get a board with a microSD card slot, then this 'standard' wiring of the SD adapter
is fine.

The  DEVEBOX stm32f407 board I used during development has an LED attached to PA1, so various errors will result in PA1 flashing.

Setting up the micro SD card and using it
-----------------------------------------

I tend to format a micro SD card with a smallish partition (less than 1GB) with 
FAT32. Create a dragon directory in the root and add rom images and disk images 
to that directory. The order in which you copy the files to this directory
determines the order in which you can cycle through them (ie. its not 
alphabetical). It only understands VDK disk files.

You also need to copy a DOS ROM to the root of the SD card, and call it
dragondos.rom.  I've used Dragon DOS 1.0, but you can use SuperDOS as well

If you then plugged the stm32f4 board in as described, then the Dragon should
boot and see a DOS rom. If you typed DIR you would get a listing of the first
disk you copied to the dragon directory.

If you press NEXT, then do a DIR again (or power off/on the Dragon) then you 
should get a directory listing of the 2nd disk you copied to the dragon 
directory and so on. PREV can be used to go to the previos disk image.

It's not a bad idea to power the stm32f4 board seperately so you can power off/on
the dragon when necessary without resetting the stm32f4 board to its first disk 
image (ie. make sure GND is connected from the Dragon to the stm32f4 board, but
leave +5V disconnected). You can put ROM images in the dragon directory as well. If you pressed
NEXT or PREV to load a ROM image, your Dragon would probably crash because it
would be like pulling out the DOS cartridge and swapping it quickly. ie. it's 
best to power off/on the Dragon.

There is also a special ROM called menu.rom. If you have built it using lwtools
(see the build.sh script), you can copy menu.rom to the root of the SD card as
well. If you power off your Dragon, and reset the stm32f4 board, the Dragon
should now boot to a menuing system called KCDFS that lists the disk images
in a simple paged menu setup.  You can then select a disk image using a letter
key. The Dragon will now cold reboot. If you selected a disk, you should have
booted Dragon DOS or similar and a DIR will show you the contents of the disk
 you selected. If you selected a ROM
it should boot directly into that ROM.

With the menu.rom, the NEXT and PREV keys still operate as they should. So if 
say you had a disk image for a game. And the next disk was a blank disk you used
for game saves, then you just press NEXT when the game asks to save, and press
PREV to get back to the game disk. It only emulates one disk drive.


Copying the firmware to the stm32f407 board
-------------------------------------------

There are lots of options for writing firmware with the stm32 chips. There is 
an example of using dfu-util in the transfer.sh script. In order for this to 
work you would need to set the BOOT0 and or BOOT1 settings such that plugging
the board in via usb will show a DFU device. Then you can run transfer.sh. Remove
the BOOT0 or BOOT1 jumpers after you do this.

KCDFS
-----

In the kcdfs directory is menu.s. It's a 6809 assembly program for the Dragon
that can communicate to the stm32f4 board in order to show a list of all the 
files in the dragon directory of the SD card. You need lwtools to assemble it
into menu.rom that you need to put in the root of the SD card.

After reset of the stm32f4 board it should load menu.rom and present it to the
Dragon. So if you want to 'get back to the kcdfs menu', you can power down the
Dragon and hit reset on the stm32f4 board, then power on the Dragon. Sometimes
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

 - kcdfs writes an 0x80 to 0xff50. That triggers the main thread of the 
   smt32f4 board to do a directory listing of the dragon directory.
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
   The Dragon would then write a 0x0100 to the 0xff54/0xff55 address register
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
0xff50 - command register
0xff51 - spare
0xff52/0xff53 - number of files returned in a directory listing. In little endian (so 0xff52 is the low byte)
0xff54/0xff55 - address register into a directory buffer
0xff56        - byte to read from the directory buffer OR byte to write to the directory buffer
```

Technical
---------

PC0 will interrupt on the +ve edge of E. In the Dragon 32 the E clock is high for a 
little over 500ns. The stm32f4 will start its ISR routine maybe 100 to 150ns into
the high part of the E clock. The 6809 address and data lines should be stable by 
then. Then there is a bunch of decision stuff such as 

 - Is it a ROM read?
 - Is it a P2 peripheral access?

A real Dragon with the DOS cart has a WD2793 or similar at 0xff40 to 0xff43. There
is a latch at 0xff48 that is used for motor control and drive select and a few other
things. 

A key difference between this and the previous floppy emulation stuff I've done is 
that the Dragon uses interrupts. The DRQ from the FDC goes to the CART cartridge pin
which is an edge trigger on one of the 6821s. And the INTRQ goes through some gates
to NMI on the 6809. Essentially bit 5 of that latch at 0xff48 can mask or unmask the
INTRQ. If the latch has bit 5 high then a high on INTRQ will drive NMI low causing
an NMI interrupt.

This interrupt stuff ended up quite interesting as you need to delay it a bit. For
example at the point where the stm32f4 decides that DRQ should go high, it actually
has to delay by quite a few E cycles before it does it.

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

The Dragon _RESET line is monitored when the stm32f4 board starts up , and waits 
for the Dragon32 to come out of reset.

Thanks
------

I will note too that the xroar emulator and it's source was extremely helpful for
figuring out the interactions with the FDC (http://www.6809.org.uk/xroar/), even
though the floppy chip emulation code is still based mostly on fMSX.

Also the source code for Dragon DOS was enormously helpful too.
https://github.com/prime6809/DragonDOS



