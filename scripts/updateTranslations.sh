#!/bin/bash

tx pull -af

pushd po
    rm LINGUAS
    for i in *.po ; do
        echo `echo $i|sed 's/.po$//'` >> LINGUAS
    done
popd