<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Tetris on an 8x20 board rendered as 640x480 VGA (TinyVGA PMOD). The board is stored in a 160-bit circular shift register that rotates one bit per clock; since 800 = 5 x 160, the ring phase is a fixed function of the horizontal pixel position, so each pixel reads its cell without a RAM. Game logic runs from the 25.175 MHz pixel clock. Audio is output on uio[7].

## How to test

Connect a TinyVGA PMOD to the outputs and a VGA monitor. Use ui[0] to move left, ui[1] to move right, ui[2] to rotate and ui[3] to drop fast. Reset with rst_n. Audio (square wave) is on uio[7].

## External hardware

TinyVGA PMOD, VGA monitor, 4 buttons on ui[0..3], optional speaker/audio PMOD on uio[7].
