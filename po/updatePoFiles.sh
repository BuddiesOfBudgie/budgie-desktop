#!/bin/bash

#!/bin/sh
tx pull -a --minimum-perc=100

rm LINGUAS

for i in *.po ; do
    echo `echo $i|sed 's/.po$//'` >> LINGUAS
done