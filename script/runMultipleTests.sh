#!/bin/bash

AllNodes=`cat script/allnodes`
Mode="pb"
./script/preciseTime.sh
./script/runMultiDCBenchmark.sh "$AllNodes"  antidote 2 2 1 $Mode 
