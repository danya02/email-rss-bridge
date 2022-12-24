#!/bin/bash

# Redirect stdin to a file in /tmp
while read line
do
  echo "$line" >> /tmp/stdin
done