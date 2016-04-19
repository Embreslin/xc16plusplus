#!/bin/sh
# Run a C/C++ program inside the sim30 simulator shipped with XC16
#   Usage: ./compile_and_sim30.sh <source-files...>
# If at least one C++ file is present, C++ support files are automatically
# linked in too.
# The XC16DIR environment variable must be set, e.g.
#   XC16DIR=/opt/microchip/xc16/v1.23

THISDIR="$(realpath "$(dirname "$0")")"
SUPPORTFILESDIR=$THISDIR/../support-files

if [ "$XC16DIR" == "" ];
then
	echo "Error: \$XC16DIR is not set!" >&2
	exit 1
fi

if [ "$TARGET_CHIP" == "" ];
then
	echo "Error: \$TARGET_CHIP is not set!" >&2
	exit 1
fi

if [ "$TARGET_FAMILY" == "" ];
then
	echo "Error: \$TARGET_FAMILY is not set!" >&2
	exit 1
fi

if [ "$SIM30_DEVICE" == "" ];
then
	echo "Error: \$SIM30_DEVICE is not set!" >&2
	exit 1
fi

CFLAGS=(-mno-eds-warn -no-legacy-libc -mcpu="$TARGET_CHIP")
CXXFLAGS=("${CFLAGS[@]}" -I$SUPPORTFILESDIR -fno-exceptions -fno-rtti -D__bool_true_and_false_are_defined -std=c++0x)
LDSCRIPT="$XC16DIR/support/$TARGET_FAMILY/gld/p$TARGET_CHIP.gld"
LDFLAGS=(--local-stack -p"$TARGET_CHIP" --report-mem --script "$LDSCRIPT" --heap=512 -L"$XC16DIR/lib" -L"$XC16DIR/lib/$TARGET_FAMILY")
LIBS=(-lc -lpic30 -lm)

function __verboserun()
{
	echo "+ $@" >&2
	"$@"
}

set -e
TEMPDIR=$(mktemp -d)
trap "rm -rf '$TEMPDIR'" exit

declare -a OBJFILES
CXX_SUPPORT_FILES=false

for SRCFILE in "$@";
do
	case "$SRCFILE" in
		*.c)
			__verboserun "$XC16DIR/bin/xc16-gcc" "${CFLAGS[@]}" \
				-c -o "$TEMPDIR/$SRCFILE.o" "$SRCFILE"
			OBJFILES+=("$TEMPDIR/$SRCFILE.o")
			;;
		*.cpp)
			if ! $CXX_SUPPORT_FILES;
			then
				CXX_SUPPORT_FILES=true
				__verboserun "$XC16DIR/bin/xc16-g++" \
					"${CXXFLAGS[@]}" -c -o \
					"$TEMPDIR/minilibstdc++.o" \
					"$SUPPORTFILESDIR/minilibstdc++.cpp"
				OBJFILES+=("$TEMPDIR/minilibstdc++.o")
			fi
			mkdir -p "$(dirname "$TEMPDIR/$SRCFILE.o")"
			__verboserun "$XC16DIR/bin/xc16-g++" "${CXXFLAGS[@]}" \
				-c -o "$TEMPDIR/$SRCFILE.o" "$SRCFILE"
			OBJFILES+=("$TEMPDIR/$SRCFILE.o")
			;;
	esac
done

__verboserun "$XC16DIR/bin/xc16-ld" "${LDFLAGS[@]}" -o "$TEMPDIR/result.elf" \
	"${OBJFILES[@]}" "${LIBS[@]}" --save-gld="$TEMPDIR/gld" >&2
__verboserun "$XC16DIR/bin/xc16-bin2hex" "$TEMPDIR/result.elf"

cat > "$TEMPDIR/sim30-script" << EOF
ld $SIM30_DEVICE
lp $TEMPDIR/result.hex
rp
io nul $TEMPDIR/output.txt
e
q
EOF

set +e
__verboserun timeout 10s "$XC16DIR/bin/sim30" "$TEMPDIR/sim30-script" >&2
case "$?" in
	0)
		echo "sim30 succeeded!" >&2
		cat "$TEMPDIR/output.txt"
		;;
	124)
		echo "Simulation timed out (killed after 10 seconds)"
		exit 1
		;;
	*)
		exit 1
		;;
esac
