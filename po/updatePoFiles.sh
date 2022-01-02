#!/bin/bash

for file in `find -name "*.po"`; do
    msgmerge --no-wrap $file budgie-desktop.pot -o $file
    msgattrib --output=${file} --no-obsolete --no-wrap $file
done