#!/bin/sh

lwasm -f raw --list -o menu menu.s
./pad-to-8k.sh menu

