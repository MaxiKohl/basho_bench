#!/bin/bash

sudo erl -pa script -name setter@localhost -setcookie antidote -run getStat get_stat -run init stop > stat/`date +"%Y-%m-%d-%H:%M:%S"` 
