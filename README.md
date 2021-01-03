# Zigominoes

Find the unique 'ominoes' that exist for a given number of squares.

Examples:
 - Dominoes (2-ominoes): There is only one of these, two squares joined
 - Tetrominoes (4-ominoes): Tetris blocks
 - The board game 'Blokus' has all ominoes up to size 5
 - The single 1-omino is just a single square

Based on https://github.com/LewisGaul/pyominoes.

Implemented in Zig 0.7.

Run the program with `zig build run`.

Run tests with `zig test src/main.zig`.

Example run:
```
$zig build run
debug(main): Running...
Set of 1 1-ominoes:
#
--------
Set of 1 2-ominoes:
..
##
--------
Set of 2 3-ominoes:
...
...
###
--------
...
#..
##.
--------
Set of 5 4-ominoes:
....
....
....
####
--------
....
....
#...
###.
--------
....
....
.#..
###.
--------
....
....
##..
##..
--------
....
....
.##.
##..
--------
```
