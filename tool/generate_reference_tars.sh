echo "--format=posix"
tar --create --verbose --file=reference/posix.tar --owner=1 --group=2 --format=posix reference/res/

echo "--format=gnu"
tar --create --verbose --file=reference/gnu.tar --owner=1 --group=2 --format=gnu reference/res/

echo "--format=v7"
# v7 can't store long names at all
tar --create --verbose --file=reference/v7.tar --owner=1 --group=2 --format=v7 reference/res/test.txt

echo "--format=ustar"
tar --create --verbose --file=reference/ustar.tar --owner=1 --group=2 --format=ustar reference/res/

echo "truncated --format=posix"
tar --create --file - --owner=1 --group=2 --format=posix reference/res/ | head --bytes=1k > reference/bad_truncated.tar