# Zigominoes

Calculate the number of unique 'ominoes' exist for a given number of squares.

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
#..
##.
--------
...
...
###
--------
Set of 5 4-ominoes:
....
....
.##.
##..
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
....
####
--------
```
