#!/bin/sh
# tools/mkcard.sh ENGINE OUT: upstream's cities (OUT/CITIES/*.CTY) and scenarios
# (OUT/SNRO.111 ... 888) into the app's folder, their names in capitals
E=$1
O=$2
mkdir -p "$O/CITIES"
for f in "$E"/cities/*.cty; do
  n=$(basename "$f" .cty | tr a-z A-Z)
  cp "$f" "$O/CITIES/$n.CTY"
done
for n in 111 222 333 444 555 666 777 888; do
  cp "$E/res/snro.$n" "$O/SNRO.$n"
done
