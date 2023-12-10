rm -r /tmp/fuzz
mkdir /tmp/fuzz
dart compile exe tool/fuzz.dart -o /tmp/fuzz/fuzz.exe

while true; do
   radamsa -o /tmp/fuzz/gen-%n -n 100 reference/**/*.tar
   /tmp/fuzz/fuzz.exe /tmp/fuzz/gen-*
   test $? -gt 127 && break
done
