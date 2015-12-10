#!/bin/bash

./script/command_to_all.sh "cd basho_bench && git stash && git pull"
./script/command_to_all.sh "./basho_bench/masterScripts/config.sh" 
./script/makeRel.sh local_specula_read
./script/makeRel.sh local_specula_read

./script/copy_to_all.sh ./script/allnodes ./basho_bench/script 
./script/command_to_all.sh "./basho_bench/masterScripts/config.sh" 
