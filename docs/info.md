<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

A compact Space Invaders for a single tile, with 640x480 VGA output (TinyVGA PMOD) and 1-bit sound.

A formation of 8x4 invaders marches across the screen and steps down every time it touches an edge.
The player has one shot on screen at a time and the invaders fire one shot back.
There is no framebuffer: every pixel is computed on the fly from a handful of registers
(32 "alive" bits, formation position, player and bullet positions). Collisions, edge detection and
choosing which invader fires are all detected while the picture is being drawn, so they cost almost no logic.

The formation speeds up as invaders are destroyed. Clearing all 32 starts a new wave.
From the second wave on, the invaders' shot falls twice as fast and is fired again as soon as it is gone.
The score (top left) counts 10 points per invader and the remaining lives are shown top right.
The game ends when the player loses all 3 lives or the invaders reach the player's row.

The top bar also shows "LACSS 2026 PANAMA" (IEEE Latin America & the Caribbean Semiconductor Summit),
drawn from a small column ROM in a 5-pixel-high font. On the die itself there is a 16x16 um "DP" gear
logo drawn in met4 next to the logic.

## How to test

Connect a TinyVGA PMOD and a VGA monitor, and buttons to the inputs:

- ui[0]: move left
- ui[1]: move right
- ui[2]: fire (also restarts the game after game over)

Reset with rst_n. Sound is a square wave on uio[7]: marching beat, shot, explosion and player hit.

## External hardware

TinyVGA PMOD, VGA monitor, 3 buttons on ui[0..2], optional speaker/audio PMOD on uio[7].
