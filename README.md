ti994a-rom-grom-ram-and-floppy-emulator
=======================================

ROM, GROM, 32K RAM expansion and FDC controller emulator for the TI99/4A computer
using a stm32f407 board. Also can emulate the p-card.

More info at   https://www.kernelcrash.com/blog/the-ti-99-4a

Heavily based on all the other rom/fdc emulators at https://www.kernelcrash.com


Overview
--------
- Emulates ROMs, GROMS, the 32K expansion and the TI Floppy controller with three drives attached.
- Take a cheap STM32F407 board (US$10 or so 'before the chip shortage'). ebay/aliexpress list several
  different stm32f407vet6/vgt6 boards with micro-SD adapters. Wire it directly to the
  TI 99/4A IO connector on the right hand side.
- Make a FAT32 partition on a micro SD card and put rom and dsk disk images on it.
- Plug the micro SD into the STM32F4 board.
- The STM32F4 board presents a rom, groms, the 32k expansion and the Floppy Controller in real time 
- Also, KCTFS is a TI native menu program that lists programs on the SD card and allows you to select them.


Wiring it
---------

Using a STM32F407VET6 or STM32F407VGT6 board
```
   PA2         - wire a button between it and GND. No need for a pullup. This is 'NEXT'
   PA3         - wire a button between it and GND. No need for a pullup. This is 'PREV'
   PA4         - wire a button between it and GND. No need for a pullup. This is 'MENU'

   PE15 to PE0 - A0(MSB) to A15(LSB)
   PD15 to PD8 - D0(MSB) to D7(LSB)

   PC0         - _MEMEN
   PC1         - _WE
   PC2         - DBIN

   PC3         - CRUCLK

   PC5         - _RESET

   GND         - GND

See notes below on CRUIN
```
Looking at the IO slot on the side of the TI 99/4A, with connections to the stm32f407 listed. I have used 
the TI pin naming of the Address and databus pins. TI (in this era) used a numbering scheme that is the opposite of
other vendors. A15 is the least significant bit of the address bus. A0 is the most significant. D7 is the least
significant bit of the data bus. D0 is the most significant.
```
Pins 1 and 2 are closest to the front of the TI 99/4A

       TOP               BOTTOM
       ---               ------

       2  _SBE             1  +5V
       4  _EXT_Int         3  _RESET - PC5
       6  A10 - PE5        5  A5 - PE10
       8  A11 - PE4        7  A4 - PE11
      10  A3 - PE12        9  DBIN - PC2
      12  READY           11  A12 - PE3
      14  A8 - PE7        13  _LOAD
      16  A14 - PE1       15  A13 - PE2
      18  A9 - PE6        17  A7 - PE8
      20  A2 - PE13       19  A15 - PE0
      22  CRUCLK - PC3    21  GND - GND
      24  03_CLK          23  GND - GND
      26  _WE - PC1       25  GND
      28  _MBE            27  GND
      30  A1 - PE14       29  A6 - PE9
      32  _MEMEN - PC0    31  A0 - PE15
      34  D7 - PD8        33  CRUIN - See note below
      36  D6 - PD9        35  D4 - PD11
      38  D5 - PD10       37  D0 - PD15
      40  D1 - PD14       39  D2 - PD13
      42  D3 - PD12       41  Hold/IAQ
      44  Sound In        43  -5V

CRUIN - Either connect it to a 3.3K resistor that goes to GND (ie. a pull down) OR
        Edit your DISK.BIN ROM to bypass the drive detection code (More detail further down)
```
If you get a board with a microSD card slot, then the 'standard' wiring of the SD adapter
is fine.

The  DEVEBOX stm32f407 board I used during development has an LED attached to PA1, so various errors will result in PA1 flashing.

It is simpler if you just tie the GND pins of the STM32407 board to the TI 99/4A , and power the stm32407 board separately from a 
USB cable. This just makes it easier to cycle through games on the SD card while the TI 99/4A is turned off.

Setting up the micro SD card and using it
-----------------------------------------

I tend to format a micro SD card with a smallish partition (less than 1GB) with 
FAT32. 

  - Copy the ti-kctfs.bin file to the root of the SD card
  - Copy the DISK.BIN DSR for the FDC to the root of the SD card and rename it to ti-disk.bin. I used one with md5 3169cfe66687d5b9ed45a69da5a12817
  - Create a directory called 'ti994a' in the root of the SD card
  - Create a directory for each game or application within the 'ti994a' directory and put the related ROM, GROM and DSK files in to that directory.
    The suffix of a filename is used to determine what to do with the file. C.BIN and D.BIN files ends up as ROMs. G.BIN files end up as the GROM. 
    .DSK files end up as disks. Anything else is treated like an 'up to 32K ROM'. Only Single Sided Single Density (SSSD) and Double Sided Single
    Density (DSSD) raw dsk images are supported (ie. 92160 or 184320 bytes). You can have up to three disk images in the one directory. The DSK1
    image needs to end in .DSK or .DSK1, the DSK2 image must end in .DSK2. The DSK3 image must end in .DSK3
    Some examples:
```
   ti994a/ti-invaders/
                      ti-invadersG.BIN
                      ti-invadersC.BIN

   ti994a/demonattack/
                      XB25C.BIN
                      XB25D.BIN
                      XB25G.BIN
                      Demonattxb.dsk

   ti994a/adventureland/
                       phm3041G.BIN
                       adventureland.dsk

   ti994a/zork1/
                      XB25C.BIN
                      XB25D.BIN
                      XB25G.BIN
                      Zork1.DSK
                      Zork1SaveDisk.dsk2  

   ti994a/dsku412/
                      DSKU412G.BIN
                      testdisk.dsk
                      testdisk2.dsk2
                      testdisk3.dsk3
```

Power on the stm32f407 board first. Then power on the TI 99/4A. Once you 'press a key' you should see KCTFS as the number 2 option. Select it. You should then
get a paged listed of the directories you created on the SD card. The order is 'the order you created the directories in'. To select a program, just hit
a letter key and the TI-99/4A should reboot. If you 'press a key' you should see 1. TI BASIC and 2. "the thing you selected in the kctfs menu". Press '2' to 
start your application.

After you've run a program you can try to reset the TI-99/4A with FCTN-= or if that does not work, turn the TI-99/4A off and on. If you pressed a key, 
you would see the same program you last ran in the list (assuming the stm32f407 board is powered separately). If you want to get back to the KCTFS menu, 
press the MENU button, then press FCTN-= on the TI-99/4A. The TI/99-4A should reboot and then you can select KCTFS again.

The NEXT and PREV buttons allow you to step through the directories on the SD card without having to go back to the KCTFS menu. Again, they are in the
order you created the directories.

You can have up to three disk images at the moment, and those disks will appear as DSK1, DSK2 and DSK3. Primary support is for the raw 92160 byte disk images,
but 184320 byte DSSD images should also work.

Many games require TI Extended Basic to autoboot. I found v2.5 tended to work best for me, so use that. In theory you would need to have a copy
of the XB25 ROM and GROM files in the same directory as the dsk image you wanted to autoboot.

Compiling the firmware
----------------------

Use the ARM GNU Toolchain from developer.arm.com. I only use linux for compiling, so have no idea how to do it on other platforms.

You will need the STM32F4DISCOVERY board firmware package from st.com. This is called STSW-STM32068.

Just type 'make' to build the firmware.

Use xdt99 (endlos99.github.io/xdt99) to assemble the KCTFS code. Details of how to run it are in the KCTFS source.


Copying the firmware to the stm32f407 board
-------------------------------------------

There are lots of options for writing firmware with the stm32 chips. There is 
an example of using dfu-util in the transfer.sh script. In order for this to 
work you would need to set the BOOT0 and or BOOT1 settings such that plugging
the board in via usb will show a DFU device. Then you can run transfer.sh. Remove
the BOOT0 or BOOT1 jumpers after you do this.

KCTFS
-----------

KCTFS is a native 9900 assembly program to present a menu of the directories under the 'ti994a' directory on the SD card. It interacts 
with the stm32f407 board by using the 5fe0 to 5fee addresses just below the addresses for the Floppy Disk Controller. There is a simple
protocol that allows it to ask the stm32f407 to generate a directory listing, then get the content of that listing and then once
a user selects an item, the items name is written back to the stm32f07 and a command is issued to 'swap the program out' and reset the
TI-99/4A.

The protocol works like this (NB: this is different to earlier versions)

 - kctfs writes an 0x80 to 0x5fe8. That triggers the main thread of the
   stm32f4 board to do a directory listing of the 'ti994a' directory.
   The stm32f4 board will write this directory listing into its own
   memory in the form of two structures. One a list of 16bit offsets to
   filename strings, and another all the filename strings together.

 - kctfs polls 0x5fe0 to see when bit 7 goes low. That means the file listing
   process has completed. kctfs now writes a sort of magic 0x33 to 0x5fe8
   to close out the directory load command.

 - kctfs now reads a count of the number of files in the directory. 0x5fe2 is
   the LSB, 0x5fe4 is MSB. There is a limit to the number of files as
   defined by MENU_MAX_DIRECTORY_ITEMS in defines.h

 - the list of subdirectories in the 'ti994a' directory is accessed by 
   first accessing the list of 16 bit offsets, then the appropriate 
   filename strings. To access the stm32f4's memory an address register
   is loaded by the TI. 0x5fea (LSB) and 0x5fec (MSB) are the address
   registers to write to. The memory map of this special 
   address space is:

     0x0000 - where to write the name of the program to load
     0x0100 - Start of a series of 16 bit words, which are offsets into the 
              special address space where the filename strings are stored.
     0x0900 - Start of the filename string storage. This is just a series of
              of null ending strings making up the contents of the 'ti994a' 
              directory on the SD card. The last filename has two zero bytes
              following it.

   So the idea is that if you want to access the 1st filename you would:

     - load the address register with 0x0100. So write 0x00 to 0x5fea and
       0x01 to 0x5fec.
     - Read from the data register 0x5fe6 to get the LSB, and again read
       0x5fe6 again to get the MSB of the 16 address where the string is
       stored (ie. the address register auto increments). Chances are you
       would read 0x00 then 0x09, so the address of the first string would
       be 0x0900.
     - Write this new address to the address registers. eg. 0x00 to 0x5fea
       and 0x09 to 0x5fec
     - Start reading from the data register 0x5fe6 to get the bytes for the 
       filename ending in a 0x00.

   The table of 16 bit offsets makes it quick for the TI to page backwards and
   forwards to different pages of 20 entries. 

 - kctfs lets a user select a file. The name selected is then copied in to the
   0x0000 offset of the stm32f4. ie. the TI-99/4A writes a 0x0000 to the
   0x5fea/0x5fec address register and then 'writes' the filename one byte
   at a time to 0x5fee including the trailing 0x00 byte.

   kctfs normally runs as a ROM in the 0x6000-07fff region. It's about to
   trigger the stm32f4 to overwrite that region, so it copies part of itself
   into RAM and continues execution there.

   Then an 0x40 is written to 0x5fe8. That triggers the
   main thread of the stm32f4 board to look inside the subdirectory selected
   and load in the ROM file(s) and GROM file and if there is a dsk image
   it will prepare that image for loading.

 - kctfs can poll the 0x5fe0 address to check when bit 6 goes low. That signifies
   that the stm32f407 has finished loading from SD card. kctfs then needs to
   write the magic 0x33 command to 0x5fe8 to end the command. 

   Then kctfs initiates a reset of the TI-99/4A. When it reboots, the selected ROM
   or GROM is presented to the TI-99/4A and the user selects it from the initial
   startup menu.


PCARD support
-------------

PCARD support is off by default. You'll need to edit the Makefile to enable it. 
The main flag is the ENABLE_PCARD one, but the ENABLE_PCARD_ACTIVITY_LED flag
will flicker PA1 when there is activity to the PCARD (the PCARD can be slow so
this is to give some hint that it hasn't crashed).

```
CFLAGS += -DENABLE_PCARD
CFLAGS += -DENABLE_PCARD_ACTIVITY_LED
```

You will need the file dumps of the ROMs and GROMs in the pcard. And you'll
need the DSK images for the disks you want to use (they have to be normal
90K or 180K ones).

Basically what you do is create a new sub directory under ti994a on your
microSD card ('pcard-test1' in the example below) and put the DSK images
you want to use. I have the disks for Pascal. DSK1 is the Compiler (I 
eventually worked out that USES SUPPORT; tends to prefer the compiler as
the first disk). DSK2 is the Editor-Filer. DSK3 is the Assembler/Linker. 

Next create a subdirectory below it called 'pcard' and place the required
ROM and GROM files in it. They have to have the filenames shown below. The
rom0 file is the 4K ROM, the rom1 file is the 8K ROM. The grom0 to 7 files
are the eight GROM files.

```
ti994a/pcard-test1/
ti994a/pcard-test1/COMPILER.DSK
ti994a/pcard-test1/EDT-FIL.DSK2
ti994a/pcard-test1/ASM-LNK.DSK3
ti994a/pcard-test1/pcard
ti994a/pcard-test1/pcard/pcode_grom0.u11
ti994a/pcard-test1/pcard/pcode_grom1.u13
ti994a/pcard-test1/pcard/pcode_grom2.u14
ti994a/pcard-test1/pcard/pcode_grom3.u16
ti994a/pcard-test1/pcard/pcode_grom4.u19
ti994a/pcard-test1/pcard/pcode_grom5.u20
ti994a/pcard-test1/pcard/pcode_grom6.u21
ti994a/pcard-test1/pcard/pcode_grom7.u22
ti994a/pcard-test1/pcard/pcode_rom0.u1
ti994a/pcard-test1/pcard/pcode_rom1.u18
```

Those pcard files I found in an archive for use with MAME.

Now boot up the TI-99/4A. Go straight in to kctfs, find your 'pcard-test1' or
whatever you called it and select. Now the TI-99/4A reboots and instead of the
usual 'press any key' screen, you just have a cyan screen for quite some time
(this is where that activity LED comes in handy). Eventually you should see
'System Initialised' and the top menu of the p-system.


Technical (for the TI 99/4A)
----------------------------

The TI99/4A is quite a bit different to other home computers of the era. The CPU
is 16 bit, yet the external bus is 8 bit. This means the main memory cycle is
quite unusual. _MEMEN goes low at the start of a memory bus cycle, but it's 
always a 16 bit operation split into at least two halves. The first half is with the
lowest address bit A15 going high, then half way through the cycle it generally 
goes low.

So the stm32f407 interrupts on the -ve edge of _MEMEN, but it needs to continually 
watch for changes in the address bus to pick up the change to the lowest address
bit and consequently do what is required (eg. present a different byte on to the
address bus).

Also the _WE pin can change multiple times during a bus cycle, so this has to be
monitored during the cycle as well.

The interrupt routine that services _MEMEN needs to:

 - see if its a read or write to the normal 8K ROM range ; 0x6000 - 0x7fff
 - see if its a read or write to the 32K expansion which is in 0x2000 - 0x3fff
   and 0xa000 - 0xfff.
 - See if its a read or write to the GROM control addresses at 0x9800/0x9802 and 
   0x9c00/0x9c02.
 - See if its a read to the DSR rom at 0x4000 - 0x5fef. The KCTFS menu control 
   interface steals 16 bytes of this at 0x5fe0.
 - See if its a read or write to the Floppy Controller chip at 0x5ff0 - 0x5fff

In addition we have a separate interrupt on the -ve edge of CRUCLK. This is to 
catch CRU output requests (CRU is a bit setting/resetting/reading interface
that the TMS9900 has). We are only interested in the 0x11xx CRU output bits as 
these relate to the Floppy Disk Controller. Three bits are used for drive selection
(as the most common FDC could handle up to 3 disk drives), another bit is for side
select, another for head loading and so on. In theory we should care about the
drive selection bits but we don't.

CRU is also used for reading. A key part of the DSR roms floppy initialisation
is to figure out how many drives are attached. The Floppy expansions hardware
had some sort of pass through where the 3 disk selection bits could be read back.
ie. if you set the drive select bit for drive 1 low, then read back the CRU bit
for drive 1 you should get a low if the drive is connected. If its high then it
means the drive is not connected.

There aren't really any good signals to watch to check for a CRU input cycle.
The technique I came up with was to simply 

- Put a 3.3K resistor on the CRUIN pin of the IO connector to tie it to GND.

That means when the Floppy DSR rom tries to read back the disk select status of
drive one it will be low, which means DSK1 is present. Similarly when it selects
drive two, the drive two input pin will also be low and so on. So all  three 
drives will be 'present'. This is fine, as we emulate all three drives.

I have tested an alternative to this resistor on the CRUIN, and that is simply
to modify the DSR ROM. The DSR ROM I have has a sequence like this for drive
detection:
```
44d8 30e0   ldcr @>4505, r3
44da 4505
44dc 022c   ai   r12, >fffa
44de fffa
44e0 34c0   stcr r0, r3
44e2 022c   ai   r12, >0006
44e4 0006
44e6 2402   czc  r2, r0
44e8 130e   jeq  >4506      // change this to 100e to make it a branch always
44ea 04c0   clr  r0
44ec c0a9   mov  @>0058(r9), r2
44ee 0058
44f0 0222   ai   r2, >fff6
```
As per the note I added for 0x44e8, if you change it from 130e to 100e then 
it becomes a 'Jump Always' and the outcome is the same as when the resistor
is present.



Thanks
------
The TI-99/4A is quite a different machine to what I've used before, so
I depended on a lot of online resources. Some I will note below:

- The atariage ti-994a forums
- The whtech FTP site
- Thierry's tech pages. These are so so good. http://www.unige.ch/medecine/nouspikel/ti99/titechpages.htm
- Some Assembly books ; 'Introduction to assembly language for the ti home computer' and 'Learning ti994a home computer assembly language programming'
- ChibiAkumas TMS9900 pages ; https://www.chibiakumas.com/tms9900/
- The xdt99 cross dev tools ; http://endlos99.github.io/xdt99/
- The ti99sim ; https://mrousseau.org/programs/ti99sim/

As always thanks to all the other projects, especially fMSX that I have used for these floppy emulator projects

And thanks to the reader that made me a great deal on a TI-99/4A.





